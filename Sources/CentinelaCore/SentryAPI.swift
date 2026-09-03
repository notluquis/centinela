import Foundation

public enum SentryError: LocalizedError, Sendable {
    case missingCredentials
    case unauthorized
    case forbidden(String)
    case rateLimited(retryAfter: TimeInterval?)
    case http(Int)
    case unexpectedResponse(String)

    public var errorDescription: String? {
        switch self {
        case .missingCredentials:
            "No token yet. Open Settings and sign in, or paste a read-only token."
        case .unauthorized:
            "Sentry rejected the token (401). It may have been revoked or expired."
        case .forbidden(let detail):
            "The token is not allowed to do this: \(detail)"
        case .rateLimited(let wait):
            // It used to say "Retrying in 30s", and nothing retried. The header was read, put in
            // the error, printed, and ignored. Now the cycle honours it and this says what will
            // happen rather than what sounded reassuring.
            wait.map { "Sentry rate-limited this. Not asking again for \(Int($0))s." }
                ?? "Sentry rate-limited this."
        case .http(let code):
            "Sentry answered \(code)."
        case .unexpectedResponse(let what):
            "Unexpected response from Sentry: \(what)"
        }
    }
}

public struct Credentials: Sendable, Equatable {
    public var token: String
    public var organization: String
    public var host: URL

    public init(token: String, organization: String, host: URL = URL(string: "https://sentry.io")!) {
        self.token = token
        self.organization = organization
        self.host = host
    }
}

/// Sentry is about to retire a route we use.
///
/// Sentry publishes a deprecation policy: once a route starts its countdown, its responses
/// carry `X-Sentry-Deprecation-Date` and, when a successor exists,
/// `X-Sentry-Replacement-Endpoint`. Ignoring those headers is how an app finds out about a
/// change on the day it stops working, with an error that never mentions deprecation.
///
/// As of 2026-08-22 none of the five routes Centinela uses carries these headers.
public struct DeprecationNotice: Sendable, Equatable {
    public let path: String
    public let date: String
    public let replacement: String?
}

public struct SentryClient: Sendable {
    let credentials: Credentials
    /// `nil` means every project, which is what `project=-1` says to Sentry.
    let projectID: String?
    /// `nil` means every environment. Today the organization this was built for has only
    /// `production`, so nothing is being mixed. The day a `staging` appears, an unfiltered count
    /// silently folds it in, which is the kind of wrong number nobody notices.
    let environment: String?
    let session: URLSession
    /// Called when a response carries Sentry's deprecation headers.
    private let onDeprecation: (@Sendable (DeprecationNotice) -> Void)?

    public init(
        credentials: Credentials,
        projectID: String? = nil,
        environment: String? = nil,
        session: URLSession? = nil,
        onDeprecation: (@Sendable (DeprecationNotice) -> Void)? = nil
    ) {
        self.credentials = credentials
        self.projectID = projectID
        self.environment = environment
        self.onDeprecation = onDeprecation
        if let session {
            self.session = session
        } else {
            let conf = URLSessionConfiguration.ephemeral
            // Ephemeral on purpose: no disk cache, no cookies, no stored credentials. Issue
            // titles can carry business data and have no business being written anywhere.
            conf.httpShouldSetCookies = false
            conf.httpCookieAcceptPolicy = .never
            conf.urlCache = nil
            conf.requestCachePolicy = .reloadIgnoringLocalCacheData
            conf.timeoutIntervalForRequest = 20
            // `waitsForConnectivity` is FALSE on purpose, and this came from reading the docs
            // rather than watching it fail: when true, a request with no network does not fail,
            // it waits until `timeoutIntervalForResource`, whose default is SEVEN DAYS. On a
            // five-minute poll that means tasks piling up in silence and a panel that never
            // says the network is down. Failing fast is right here: the next cycle retries in
            // minutes.
            conf.waitsForConnectivity = false
            conf.timeoutIntervalForResource = 60
            self.session = URLSession(configuration: conf)
        }
    }

    // MARK: - Decoding

    /// Sentry mixes two ISO-8601 formats in the SAME response: an issue's `lastSeen` arrives as
    /// `2026-08-22T18:09:56Z` and a release's `dateCreated` as `2026-08-22T18:15:40.781127Z`.
    /// Plain `.iso8601` blows up on the second, `.withFractionalSeconds` blows up on the first.
    /// Hence both are tried.
    static let decoder: JSONDecoder = {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let withoutFraction = ISO8601DateFormatter()
        withoutFraction.formatOptions = [.withInternetDateTime]

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { inner in
            let text = try inner.singleValueContainer().decode(String.self)
            if let date = withFraction.date(from: text) ?? withoutFraction.date(from: text) {
                return date
            }
            throw DecodingError.dataCorrupted(
                .init(codingPath: inner.codingPath, debugDescription: "not an ISO-8601 date: \(text)")
            )
        }
        return decoder
    }()

    // MARK: - Transport

    func get(_ path: String, _ query: [URLQueryItem]) async throws -> Data {
        guard !credentials.organization.isEmpty else { throw SentryError.missingCredentials }
        let full = "api/0/organizations/\(credentials.organization)/\(path)/"
        return try await getAtPath(full, query)
    }

    /// Same as `get`, but with the full path: some endpoints do NOT hang off an organization,
    /// and `organizations/` is exactly the one needed to find out which organization it is.
    func getAtPath(_ path: String, _ query: [URLQueryItem]) async throws -> Data {
        guard !credentials.token.isEmpty else { throw SentryError.missingCredentials }
        // The trailing slash is NOT cosmetic: `…/projects` without it returns a flat 404, with
        // no redirect (measured against sentry.io). `appendingPathComponent` keeps it; replacing
        // this line with something that drops it breaks the whole app with an error that never
        // mentions slashes.
        var components = URLComponents(
            url: credentials.host.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        // Only when there is something: assigning an empty array leaves the URL ending in a
        // bare `?` (`…/organizations/?`). Sentry tolerates it, but it is junk that later shows
        // up in someone else's logs and in any URL comparison.
        if !query.isEmpty { components.queryItems = query }

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
        // URLSession negotiates gzip on its own and Sentry honours it (measured: the issues
        // response arrives compressed). There is no ETag on any route of the API, so there is
        // no conditional revalidation to exploit: staying light means asking for little.
        request.setValue("centinela", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SentryError.unexpectedResponse("response without an HTTP status")
        }
        if let notice = Self.deprecation(in: http, path: path) { onDeprecation?(notice) }
        switch http.statusCode {
        case 200...299:
            return data
        case 401:
            throw SentryError.unauthorized
        case 403:
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
            throw SentryError.forbidden(detail ?? "403")
        case 429:
            let wait = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw SentryError.rateLimited(retryAfter: wait)
        default:
            throw SentryError.http(http.statusCode)
        }
    }

    func get<T: Decodable>(_ type: T.Type, _ path: String, _ query: [URLQueryItem]) async throws -> T {
        try decode(type, try await get(path, query), path: path)
    }

    func decode<T: Decodable>(_ type: T.Type, _ data: Data, path: String) throws -> T {
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw SentryError.unexpectedResponse("\(path): \(error)")
        }
    }

    /// Reads Sentry's deprecation-policy headers. `internal` so the suite can exercise it
    /// without going to the network.
    static func deprecation(in http: HTTPURLResponse, path: String) -> DeprecationNotice? {
        guard let date = http.value(forHTTPHeaderField: "X-Sentry-Deprecation-Date") else { return nil }
        return DeprecationNotice(
            path: path,
            date: date,
            replacement: http.value(forHTTPHeaderField: "X-Sentry-Replacement-Endpoint")
        )
    }

    // The members below are `internal` rather than `private` because the queries live in
    // `SentryQueries.swift`, and `private` does not reach across files even inside one type.
    // Nothing here leaves the module.

    /// Project and environment, in one place. Every query goes through here so none of them can
    /// quietly ignore the filter the user chose.
    var scope: [URLQueryItem] {
        var items = [URLQueryItem(name: "project", value: projectID ?? "-1")]
        if let environment { items.append(.init(name: "environment", value: environment)) }
        return items
    }

}

public enum TimeWindow: String, CaseIterable, Sendable {
    case oneHour = "1h"
    case sixHours = "6h"
    case twentyFourHours = "24h"
    case sevenDays = "7d"
    case fourteenDays = "14d"

    public var label: String {
        switch self {
        case .oneHour: "1 hour"
        case .sixHours: "6 hours"
        case .twentyFourHours: "24 hours"
        case .sevenDays: "7 days"
        case .fourteenDays: "14 days"
        }
    }
}

/// What the menu-bar number counts.
///
/// The default was error *events* (`events-stats`, all issue statuses), which reads next to the
/// panel's issue list as if it were the same quantity: 147 events across 3 unresolved issues
/// invites the reading that 144 are missing. They are different questions — one counts
/// occurrences, the other open issue groups — so the honest fix is to let the number answer the
/// one the reader means. `.unresolved` is the default because "how many fires are still burning"
/// is what a watch is for; `.errorEvents` stays for whoever wants raw volume.
///
/// The cost is not free and is the reason this is a choice rather than a rename: `.errorEvents`
/// rides the cheap series the cycle already fetches (937 B), while every other case adds one
/// issue-list read to each cycle — the read AGENTS.md keeps out of the periodic path. Picking one
/// of them is opting into that traffic knowingly.
public enum BadgeMetric: String, CaseIterable, Sendable {
    case errorEvents
    case unresolved
    case forReview
    case escalating
    case regressed

    /// For the Settings picker.
    public var label: String {
        switch self {
        case .errorEvents: "Error events"
        case .unresolved: "Unresolved issues"
        case .forReview: "Issues for review"
        case .escalating: "Escalating issues"
        case .regressed: "Regressed issues"
        }
    }

    /// The singular noun for the panel header. The head is the LAST word on purpose: the header
    /// pluralizes by appending "s", so "for-review issue" → "for-review issues", where "issue for
    /// review" would wrongly become "issue for reviews".
    public var noun: String {
        switch self {
        case .errorEvents: "error"
        case .unresolved: "unresolved issue"
        case .forReview: "for-review issue"
        case .escalating: "escalating issue"
        case .regressed: "regressed issue"
        }
    }
}
