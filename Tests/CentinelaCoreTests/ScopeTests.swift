import Foundation
import Testing

@testable import CentinelaCore

/// Every query has to carry the project and environment the user picked. A query that forgets is
/// not an error anyone sees: it just answers about the wrong thing.
@Suite("Query scope")
struct ScopeTests {
    private func client(_ session: URLSession, project: String? = nil, environment: String? = nil) -> SentryClient {
        SentryClient(
            credentials: Credentials(
                token: "t", organization: "example", host: URL(string: "https://sentry.example")!
            ),
            projectID: project,
            environment: environment,
            session: session
        )
    }

    @Test("With nothing picked it asks about every project and every environment")
    func defaultScope() async throws {
        let session = StubServer.session()
        StubServer.enqueue(session, "/issues/", "[]")
        _ = try await client(session).unresolvedIssues(window: .twentyFourHours)
        let asked = try #require(StubServer.requests(session).first?.path)
        #expect(asked.contains("project=-1"))
        #expect(!asked.contains("environment="))
    }

    @Test("A picked project replaces the wildcard")
    func projectScope() async throws {
        let session = StubServer.session()
        StubServer.enqueue(session, "/issues/", "[]")
        _ = try await client(session, project: "4511380596523008").unresolvedIssues(window: .twentyFourHours)
        let asked = try #require(StubServer.requests(session).first?.path)
        #expect(asked.contains("project=4511380596523008"))
        #expect(!asked.contains("project=-1"))
    }

    /// Today the organization this was built for has a single environment, so nothing is being
    /// mixed. The day a `staging` shows up, an unfiltered count folds it into the number on the
    /// menu bar without saying so.
    @Test("A picked environment travels with the query")
    func environmentScope() async throws {
        let session = StubServer.session()
        StubServer.enqueue(session, "/events-stats/", #"{"data":[]}"#)
        _ = try await client(session, environment: "production").errorSeries(window: .twentyFourHours)
        let asked = try #require(StubServer.requests(session).first?.path)
        #expect(asked.contains("environment=production"))
    }

    /// The colons are NOT percent-encoded: they are legal in a query value and `URLComponents`
    /// leaves them alone. Asserting on `%3A` passes against an imagined URL and fails against the
    /// real one.
    @Test("The four issue lists differ only in the query", arguments: [
        ("unresolved", "query=is:unresolved&"),
        ("for review", "is:for_review"),
        ("escalating", "is:escalating"),
        ("regressed", "is:regressed")
    ])
    func issueQueries(name: String, expected: String) async throws {
        let session = StubServer.session()
        StubServer.enqueue(session, "/issues/", "[]")
        let api = client(session)
        switch name {
        case "unresolved": _ = try await api.unresolvedIssues(window: .twentyFourHours)
        case "for review": _ = try await api.issuesForReview()
        case "escalating": _ = try await api.escalatingIssues()
        default: _ = try await api.regressedIssues()
        }
        let asked = try #require(StubServer.requests(session).first?.path)
        #expect(asked.contains(expected))
        #expect(asked.contains("project=-1"), "the scope must travel on every one of them")
    }
}

@Suite("Health signals")
struct HealthTests {
    private func fixture(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        )
        return try Data(contentsOf: url)
    }

    /// The join that can fail silently: `stats_v2` returns the project id as a NUMBER and
    /// `/projects/` returns it as a STRING. Measured, same organization, same day. Comparing them
    /// without converting matches nothing and the breakdown comes out empty with no error.
    @Test("Errors per project join a numeric id against a string one")
    func projectJoin() throws {
        let projects = [
            Project(id: "4511380596523008", slug: "example-api", name: "example-api"),
            Project(id: "4511816140324864", slug: "example-web", name: "example-web")
        ]
        let counts = try ProjectErrorCount.from(statsJSON: fixture("stats-by-project"), projects: projects)
        #expect(counts.count == 2)
        // Sorted by count, so the noisiest project is first.
        #expect(counts[0].slug == "example-api")
        #expect(counts[0].count == 13)
        #expect(counts[1].slug == "example-web")
    }

    @Test("A project the token cannot see still shows its count, without a name")
    func unknownProject() throws {
        let counts = try ProjectErrorCount.from(statsJSON: fixture("stats-by-project"), projects: [])
        #expect(counts.count == 2)
        #expect(counts.allSatisfy { $0.slug == nil })
        #expect(counts[0].count == 13)
    }

    @Test("A payload without `groups` fails loudly")
    func statsWithoutGroups() {
        #expect(throws: SentryError.self) {
            _ = try ProjectErrorCount.from(statsJSON: Data(#"{"start":"x"}"#.utf8), projects: [])
        }
    }

    /// Not verified against real data: the organization has no cron monitors, so the shape comes
    /// from Sentry's published OpenAPI schema and so does this fixture.
    @Test("Cron monitors decode, and muted or disabled ones are not active")
    func cronMonitors() throws {
        let monitors = try SentryClient.decoder.decode([CronMonitor].self, from: fixture("cron-monitors"))
        #expect(monitors.count == 3)
        #expect(monitors[0].isActive)
        #expect(!monitors[1].isActive, "muted")
        #expect(!monitors[2].isActive, "disabled")
    }
}
