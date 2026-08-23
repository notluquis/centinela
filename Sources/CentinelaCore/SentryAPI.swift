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
            wait.map { "Sentry rate-limited the request. Retrying in \(Int($0))s." }
                ?? "Sentry rate-limited the request."
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
    private let credentials: Credentials
    /// `nil` means every project, which is what `project=-1` says to Sentry.
    private let projectID: String?
    /// `nil` means every environment. Today the organization this was built for has only
    /// `production`, so nothing is being mixed. The day a `staging` appears, an unfiltered count
    /// silently folds it in, which is the kind of wrong number nobody notices.
    private let environment: String?
    private let session: URLSession
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

    private func get(_ path: String, _ query: [URLQueryItem]) async throws -> Data {
        guard !credentials.organization.isEmpty else { throw SentryError.missingCredentials }
        let full = "api/0/organizations/\(credentials.organization)/\(path)/"
        return try await getAtPath(full, query)
    }

    /// Same as `get`, but with the full path: some endpoints do NOT hang off an organization,
    /// and `organizations/` is exactly the one needed to find out which organization it is.
    private func getAtPath(_ path: String, _ query: [URLQueryItem]) async throws -> Data {
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

    private func get<T: Decodable>(_ type: T.Type, _ path: String, _ query: [URLQueryItem]) async throws -> T {
        try decode(type, try await get(path, query), path: path)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data, path: String) throws -> T {
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

    /// Project and environment, in one place. Every query goes through here so none of them can
    /// quietly ignore the filter the user chose.
    private var scope: [URLQueryItem] {
        var items = [URLQueryItem(name: "project", value: projectID ?? "-1")]
        if let environment { items.append(.init(name: "environment", value: environment)) }
        return items
    }

    // MARK: - The cheap calls: this is what every cycle asks for

    /// 378 ms and 937 B measured against a real organization: three times faster and eleven
    /// times lighter than fetching the issue list. This is what feeds the count and the
    /// sparkline.
    public func errorSeries(window: TimeWindow, interval: String = "1h") async throws -> EventSeries {
        let data = try await get("events-stats", [
            .init(name: "statsPeriod", value: window.rawValue),
            .init(name: "interval", value: interval),
            .init(name: "yAxis", value: "count()"),
            .init(name: "query", value: "event.type:error")
        ] + scope)
        return try EventSeries(json: data)
    }

    /// 490 ms measured. Returns the monitors' configuration, not their history.
    public func uptimeMonitors() async throws -> [UptimeMonitor] {
        try await get([UptimeMonitor].self, "uptime", [])
    }

    // MARK: - The expensive calls: only when the panel opens

    /// 1047 ms and 10.6 KB measured: the most expensive route in the API. That is why it is not
    /// in the periodic cycle: it is fetched when someone opens the panel and wants to read.
    public func unresolvedIssues(window: TimeWindow, limit: Int = 15) async throws -> [SentryIssue] {
        try await issues(matching: "is:unresolved", window: window, limit: limit)
    }

    public func issuesForReview(window: TimeWindow = .fourteenDays, limit: Int = 10) async throws -> [SentryIssue] {
        try await issues(matching: "is:unresolved is:for_review", window: window, limit: limit)
    }

    /// Issues Sentry itself flagged as getting worse. They come back with `substatus: escalating`.
    public func escalatingIssues(window: TimeWindow = .fourteenDays, limit: Int = 10) async throws -> [SentryIssue] {
        try await issues(matching: "is:unresolved is:escalating", window: window, limit: limit)
    }

    /// Issues that came back after being marked resolved (`substatus: regressed`).
    public func regressedIssues(window: TimeWindow = .fourteenDays, limit: Int = 10) async throws -> [SentryIssue] {
        try await issues(matching: "is:unresolved is:regressed", window: window, limit: limit)
    }

    /// The four issue lists differ only in the search query, so they share one call. Adding a
    /// fifth is a line, and none of them can forget the project or environment filter.
    private func issues(matching query: String, window: TimeWindow, limit: Int) async throws -> [SentryIssue] {
        try await get([SentryIssue].self, "issues", [
            .init(name: "query", value: query),
            .init(name: "statsPeriod", value: window.rawValue),
            .init(name: "limit", value: String(limit))
        ] + scope)
    }

    public func latestReleases(limit: Int = 5) async throws -> [Release] {
        try await get([Release].self, "releases", [.init(name: "per_page", value: String(limit))])
    }

    public func projects() async throws -> [Project] {
        try await get([Project].self, "projects", [])
    }

    /// Crash-free session rate for the window, as a fraction (1.0 means no crashes).
    ///
    /// `nil` rather than 0 when the organization sends no session data at all: an app with no
    /// release health configured is not an app that crashes constantly, and showing 0% would say
    /// exactly that.
    public func crashFreeRate(window: TimeWindow) async throws -> Double? {
        let data = try await get("sessions", [
            .init(name: "field", value: "crash_free_rate(session)"),
            .init(name: "statsPeriod", value: window.rawValue)
        ] + scope)
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let groups = root["groups"] as? [[String: Any]],
            let totals = groups.first?["totals"] as? [String: Any],
            let rate = totals["crash_free_rate(session)"] as? NSNumber
        else { return nil }
        return rate.doubleValue
    }

    /// Cron monitors. See `CronMonitor`: the shape comes from Sentry's published schema, not from
    /// a response, because there are none to look at yet.
    public func cronMonitors() async throws -> [CronMonitor] {
        try await get([CronMonitor].self, "monitors", [])
    }

    /// Errors per project for the window, joined against the project list so the result carries
    /// slugs rather than opaque numbers.
    public func errorsByProject(window: TimeWindow) async throws -> [ProjectErrorCount] {
        async let statsData = get("stats_v2", [
            .init(name: "field", value: "sum(quantity)"),
            .init(name: "groupBy", value: "project"),
            .init(name: "statsPeriod", value: window.rawValue),
            .init(name: "category", value: "error")
        ])
        async let projectList = projects()
        return try await ProjectErrorCount.from(statsJSON: statsData, projects: projectList)
    }

    /// The slowest transactions in the window, by 95th percentile span duration.
    ///
    /// Measured against a real organization: 5 rows in 501 ms, topped by an outbound Microsoft
    /// Graph call at 1170 ms p95 over 150 samples. This is the only route here whose response
    /// keys are decided by the request, so `field=` and the parsing in `TransactionStat` have to
    /// agree; there is a test that they do.
    public func slowestTransactions(window: TimeWindow, limit: Int = 8) async throws -> [TransactionStat] {
        let data = try await get("events", [
            .init(name: "field", value: "transaction"),
            .init(name: "field", value: TransactionStat.countField),
            .init(name: "field", value: TransactionStat.p95Field),
            .init(name: "statsPeriod", value: window.rawValue),
            .init(name: "dataset", value: "spans"),
            .init(name: "sort", value: "-" + TransactionStat.p95Field),
            .init(name: "per_page", value: String(limit))
        ] + scope)
        return try TransactionStat.from(json: data)
    }

    /// Session replays. See `Replay`: shape from the published schema, none to look at yet.
    public func replays(window: TimeWindow, limit: Int = 10) async throws -> [Replay] {
        struct Envelope: Decodable { let data: [Replay] }
        let data = try await get("replays", [
            .init(name: "statsPeriod", value: window.rawValue),
            .init(name: "per_page", value: String(limit))
        ] + scope)
        return try decode(Envelope.self, data, path: "replays").data
    }

    /// User feedback. See `UserFeedback`: shape from the published schema, none to look at yet.
    public func userFeedback(limit: Int = 10) async throws -> [UserFeedback] {
        try await get([UserFeedback].self, "user-feedback", [
            .init(name: "per_page", value: String(limit))
        ])
    }

    /// The environments that have data. Used to offer a filter only when there is more than one.
    public func environments() async throws -> [String] {
        struct Environment: Decodable { let name: String }
        return try await get([Environment].self, "environments", []).map(\.name)
    }

    /// The organizations this token can reach. Does NOT hang off an organization, hence
    /// `getAtPath`.
    ///
    /// It exists to close a hole in sign-in: the device flow hands back a token and nothing
    /// else. Without this, someone signed in successfully and the app kept saying "not
    /// configured", because `organization` was still empty and no layer reported an error.
    public func organizations() async throws -> [Organization] {
        let data = try await getAtPath("api/0/organizations/", [])
        return try decode([Organization].self, data, path: "organizations")
    }

    // MARK: - Token hygiene

    /// A read-only token CANNOT read the organization's audit log. If this call returns 200 the
    /// token carries write permissions and the widget is running with more power than it needs,
    /// which the UI then says out loud.
    ///
    /// It exists because the first token used here was `sentry-cli`'s — the same one that
    /// uploads sourcemaps and publishes releases — and it read the audit log just fine.
    public func tokenLooksReadOnly() async -> Bool {
        do {
            _ = try await get("audit-logs", [.init(name: "per_page", value: "1")])
            return false
        } catch SentryError.forbidden, SentryError.http(404) {
            return true
        } catch {
            // A network failure says nothing about the token: no accusations without evidence.
            return true
        }
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
