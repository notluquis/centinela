import Foundation

/// Sign-in with the OAuth 2.0 device flow (RFC 8628), which is what `sentry-cli` uses and what
/// Sentry documents for clients without a browser of their own.
///
/// Why this instead of asking the user to paste a token: a hand-pasted token usually comes from
/// reusing whatever was already lying around, which is the CI one, which carries write access.
/// Here the app DECLARES the scopes it needs and the user approves exactly those.
///
/// Requires Sentry 26.1.0 or newer. On older instances the endpoint does not exist and the app
/// falls back to a pasted token, which is what `AppSettings` handles.
public struct DeviceFlow: Sendable {
    /// The OAuth client id of the application registered in Sentry for Centinela.
    ///
    /// It lives in the source on purpose. RFC 8628 treats these as **public** clients: there is
    /// no secret to protect, the identifier travels in every request, and its job is to name
    /// the application on the screen where a person approves. `sentry-cli` does the same with
    /// its own. Anyone who prefers to register theirs pastes it in Settings and this one goes
    /// unused.
    public static let centinelaClientID = "ba7385bf68de9e4f134f5c3da81d1080c822f04c5578556a0786c01a453219f2"

    /// All Centinela asks for. It does not include `project:write` or `event:write`, which
    /// `sentry-cli` does request because it uploads sourcemaps.
    public static let scopes = ["org:read", "project:read", "event:read"]

    public struct Code: Sendable, Equatable {
        public let deviceCode: String
        public let userCode: String
        public let verificationURL: URL
        /// URL with the code already embedded. When the server sends it, this is the one that
        /// gets opened and the person types nothing.
        public let completeURL: URL?
        public let expiresIn: TimeInterval
        /// How often we may ask. The server can raise it with `slow_down`.
        public let interval: TimeInterval
    }

    public struct Grant: Sendable, Equatable {
        public let accessToken: String
        public let refreshToken: String?
        public let expiresAt: Date
    }

    public enum Failure: LocalizedError, Sendable, Equatable {
        case clientNotConfigured
        case deniedByUser
        case codeExpired
        case serverDoesNotSupportFlow
        case response(String)

        public var errorDescription: String? {
            switch self {
            case .clientNotConfigured:
                "Missing the OAuth client id. See the README, \"Signing in\"."
            case .deniedByUser:
                "The authorization was denied in the browser."
            case .codeExpired:
                "The code expired before it was approved. Try again."
            case .serverDoesNotSupportFlow:
                "This Sentry server does not support the device flow (needs 26.1.0 or newer). Use a token."
            case .response(let detail):
                "Sentry answered: \(detail)"
            }
        }
    }

    private let host: URL
    private let clientID: String
    private let session: URLSession

    public init(host: URL, clientID: String, session: URLSession = .shared) {
        self.host = host
        self.clientID = clientID
        self.session = session
    }

    // MARK: - Step 1: ask for the code

    public func requestCode() async throws -> Code {
        guard !clientID.isEmpty else { throw Failure.clientNotConfigured }

        let body = try await postForm("oauth/device/code/", [
            "client_id": clientID,
            "scope": Self.scopes.joined(separator: " ")
        ])
        guard
            let deviceCode = body["device_code"] as? String,
            let userCode = body["user_code"] as? String,
            let uri = body["verification_uri"] as? String,
            let url = URL(string: uri)
        else { throw Failure.response("incomplete device/code response") }

        return Code(
            deviceCode: deviceCode,
            userCode: userCode,
            verificationURL: url,
            completeURL: (body["verification_uri_complete"] as? String).flatMap(URL.init(string:)),
            // The defaults are the ones RFC 8628 prescribes when the server omits them.
            expiresIn: (body["expires_in"] as? NSNumber)?.doubleValue ?? 600,
            interval: (body["interval"] as? NSNumber)?.doubleValue ?? 5
        )
    }

    // MARK: - Step 2: wait for the person to approve

    /// Asks every `interval` seconds until the user approves, denies, or the code expires.
    /// `sleep` is injected so tests do not actually wait.
    public func waitForApproval(
        _ code: Code,
        sleep: @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    ) async throws -> Grant {
        var interval = code.interval
        let deadline = Date().addingTimeInterval(code.expiresIn)

        while Date() < deadline {
            try await sleep(interval)
            let body = try? await postForm("oauth/token/", [
                "client_id": clientID,
                "device_code": code.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
            ])
            guard let body else { continue }

            if let token = body["access_token"] as? String {
                let life = (body["expires_in"] as? NSNumber)?.doubleValue ?? 3600
                return Grant(
                    accessToken: token,
                    refreshToken: body["refresh_token"] as? String,
                    expiresAt: Date().addingTimeInterval(life)
                )
            }

            switch body["error"] as? String {
            case "authorization_pending", nil:
                continue
            case "slow_down":
                // The RFC requires raising the interval by 5 seconds every time this arrives.
                // Ignoring it makes the server keep answering `slow_down` forever.
                interval += 5
            case "access_denied":
                throw Failure.deniedByUser
            case "expired_token":
                throw Failure.codeExpired
            case .some(let other):
                throw Failure.response(other)
            }
        }
        throw Failure.codeExpired
    }

    // MARK: - Step 3: renew before it expires

    public func refresh(_ refreshToken: String) async throws -> Grant {
        let body = try await postForm("oauth/token/", [
            "client_id": clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ])
        guard let token = body["access_token"] as? String else {
            throw Failure.response((body["error"] as? String) ?? "refresh without an access_token")
        }
        let life = (body["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        return Grant(
            accessToken: token,
            // Sentry rotates the refresh token: when a new one arrives it must replace the old,
            // and when none arrives the old one still works. Storing `nil` blindly signs the
            // user out on the next renewal.
            refreshToken: (body["refresh_token"] as? String) ?? refreshToken,
            expiresAt: Date().addingTimeInterval(life)
        )
    }

    /// `sentry-cli` renews when less than 10% of the token's life remains. The same rule is
    /// copied rather than inventing one.
    public static func shouldRefresh(expiresAt: Date, life: TimeInterval, now: Date = .now) -> Bool {
        expiresAt.timeIntervalSince(now) < life * 0.1
    }

    // MARK: - Transport

    private func postForm(_ path: String, _ fields: [String: String]) async throws -> [String: Any] {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        let body = components.percentEncodedQuery ?? ""

        var request = URLRequest(url: host.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(body.utf8)

        let (data, response) = try await session.data(for: request)
        // A 404 means the instance predates 26.1.0 and the endpoint does not exist. That is a
        // different thing from a flow error and deserves a different message.
        if let http = response as? HTTPURLResponse, http.statusCode == 404 {
            throw Failure.serverDoesNotSupportFlow
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.response("body that is not JSON")
        }
        return json
    }
}
