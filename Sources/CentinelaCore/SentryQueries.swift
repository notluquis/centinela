import Foundation

// The queries live apart from the transport. `SentryClient` is how a request is made and what
// happens to the answer; this is which questions get asked. They were one file until it crossed
// four hundred lines, which is where reading it stops being free.
extension SentryClient {
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
        public func escalatingIssues(
        window: TimeWindow = .fourteenDays, limit: Int = 10
    ) async throws -> [SentryIssue] {
            try await issues(matching: "is:unresolved is:escalating", window: window, limit: limit)
        }

        /// Issues that came back after being marked resolved (`substatus: regressed`).
        public func regressedIssues(window: TimeWindow = .fourteenDays, limit: Int = 10) async throws -> [SentryIssue] {
            try await issues(matching: "is:unresolved is:regressed", window: window, limit: limit)
        }

        /// Issues someone has marked resolved. `is:resolved` is documented alongside `is:unresolved`.
        public func resolvedIssues(window: TimeWindow = .fourteenDays, limit: Int = 10) async throws -> [SentryIssue] {
            try await issues(matching: "is:resolved", window: window, limit: limit)
        }

        /// Archived (ignored) issues. Sentry renamed "ignored" to "archived"; the token is
        /// `is:archived`.
        public func archivedIssues(window: TimeWindow = .fourteenDays, limit: Int = 10) async throws -> [SentryIssue] {
            try await issues(matching: "is:archived", window: window, limit: limit)
        }

        /// Every issue regardless of status. The endpoint defaults to `is:unresolved` when the
        /// query is omitted, so "all" is an explicit EMPTY query — `query=` returns resolved and
        /// archived issues too.
        public func allIssues(window: TimeWindow = .fourteenDays, limit: Int = 10) async throws -> [SentryIssue] {
            try await issues(matching: "", window: window, limit: limit)
        }

        /// The issue lists differ only in the search query, so they share one call. Adding another
        /// is a line, and none of them can forget the project or environment filter.
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

        /// Sentry's own duration threshold for a project, in milliseconds.
        ///
        /// Measured: `bioalergia-api` answers `{"threshold":"300","metric":"duration"}`. Using this
        /// instead of a number of our own means the line between "fine" and "slow" is the one the
        /// organization already agreed on, and it moves when they move it.
        ///
        /// The value arrives as a **string**, like `issue.count` does.
        public func transactionThreshold(projectSlug: String) async throws -> Double? {
            let path = "api/0/projects/\(credentials.organization)/\(projectSlug)/transaction-threshold/configure/"
            let data = try await getAtPath(path, [])
            guard
                let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let raw = root["threshold"] as? String,
                let value = Double(raw)
            else { return nil }
            return value
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
