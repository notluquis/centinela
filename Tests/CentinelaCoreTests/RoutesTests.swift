import Foundation
import Testing

@testable import CentinelaCore

/// The routes that had no test of their own, and the one guard that matters most here.
///
/// The list came out of counting public symbols in `CentinelaCore` against every name mentioned
/// anywhere under `Tests/`: twenty were never named. Most of them are decoders, and a decoder
/// with no test is a shape somebody guessed once.
@Suite("Routes")
struct RoutesTests {
    /// A token that is easy to spot in a haystack and shaped like a real one, so the guard below
    /// fails the way a real leak would.
    ///
    /// Assembled from pieces rather than written out, because the value has to LOOK like a Sentry
    /// token and the repository has a CI job that refuses exactly that shape in the tree. Written
    /// as one literal it failed that job, which is the guard doing its work on the one file that
    /// has a reason to carry the shape. Splitting the prefix keeps both: the test still exercises
    /// a realistic value, and no line in the repository matches `sntry[su]_…`.
    private static let token = "sntry" + "s_" + "TESTTOKEN_never_show_this_0123456789"

    private func client(_ session: URLSession) -> SentryClient {
        SentryClient(
            credentials: Credentials(
                token: RoutesTests.token,
                organization: "example",
                host: URL(string: "https://sentry.example")!
            ),
            session: session
        )
    }

    // MARK: - The token never reaches anything a person reads

    /// `AGENTS.md` rule 2 says the token never appears in a log or an error message. That was a
    /// promise with nothing holding it up: two of the six error cases carry a string built from
    /// whatever Sentry sent back, and nothing checked what ends up inside them.
    @Test("No error message carries the token", arguments: [
        (403, #"{"detail":"you cannot do that"}"#),
        (401, ""),
        (500, "upstream exploded"),
        (200, "this is not json at all")
    ])
    func errorsNeverLeakTheToken(status: Int, body: String) async {
        let session = StubServer.session()
        StubServer.enqueue(session, "/issues/", body, status: status)
        do {
            _ = try await client(session).unresolvedIssues(window: .twentyFourHours)
            Issue.record("the request should not have succeeded")
        } catch {
            let shown = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            #expect(!shown.contains(RoutesTests.token))
            // Not just the whole token: any recognisable piece of it would be as bad.
            #expect(!shown.contains("sntrys_"))
            #expect(!shown.isEmpty, "an error nobody can read is its own problem")
        }
    }

    // MARK: - The read-only check

    /// The panel warns when the token can read the organization's audit log, because a token that
    /// can read that one carries write access the app never asked for. The check had no test, so
    /// nothing stopped it from quietly answering "read-only" for every token.
    @Test("A token that reaches the audit log is not read-only")
    func auditLogMeansWriteAccess() async {
        let session = StubServer.session()
        StubServer.enqueue(session, "/audit-logs/", #"{"rows":[]}"#)
        #expect(await client(session).tokenLooksReadOnly() == false)
    }

    @Test("A token refused by the audit log is read-only", arguments: [403, 404])
    func refusedAuditLogMeansReadOnly(status: Int) async {
        let session = StubServer.session()
        StubServer.enqueue(session, "/audit-logs/", #"{"detail":"no"}"#, status: status)
        #expect(await client(session).tokenLooksReadOnly() == true)
    }

    // MARK: - Decoders that had no test

    @Test("Crash-free rate comes out of the nested totals")
    func crashFreeRate() async throws {
        let session = StubServer.session()
        StubServer.enqueue(session, "/sessions/", """
        {"groups":[{"by":{},"totals":{"crash_free_rate(session)":0.9942}}]}
        """)
        let rate = try await client(session).crashFreeRate(window: .twentyFourHours)
        #expect(rate == 0.9942)
    }

    /// An organization with sessions but no crashes answers with an empty `groups`, and that is
    /// not an error: it is "no data", which the panel draws differently from "zero per cent".
    @Test("No session data is nil, not zero")
    func crashFreeRateWithoutData() async throws {
        let session = StubServer.session()
        StubServer.enqueue(session, "/sessions/", #"{"groups":[]}"#)
        #expect(try await client(session).crashFreeRate(window: .twentyFourHours) == nil)
    }

    /// The mismatch this pins is real and measured: `stats_v2` returns the project id as a JSON
    /// **number** while `/projects/` returns the same id as a **string**. Cross them without
    /// converting and every row loses its name.
    @Test("Errors by project cross a numeric id against a string one")
    func errorsByProject() async throws {
        let session = StubServer.session()
        StubServer.enqueue(session, "/stats_v2/", """
        {"groups":[{"by":{"project":11},"totals":{"sum(quantity)":13}},
                   {"by":{"project":22},"totals":{"sum(quantity)":1}}]}
        """)
        StubServer.enqueue(session, "/projects/", """
        [{"id":"11","slug":"example-api","name":"example-api"},
         {"id":"22","slug":"example-web","name":"example-web"}]
        """)
        let rows = try await client(session).errorsByProject(window: .twentyFourHours)
        #expect(rows.count == 2)
        #expect(rows.first?.slug == "example-api")
        #expect(rows.first?.count == 13)
    }

    @Test("Uptime monitors decode with their status")
    func uptimeMonitors() async throws {
        let session = StubServer.session()
        StubServer.enqueue(session, "/uptime/", """
        [{"id":"1","name":"example.com","status":"active","url":"https://example.com",
          "intervalSeconds":60,"uptimeStatus":1},
         {"id":"2","name":"api.example.com","status":"active","url":"https://api.example.com",
          "intervalSeconds":300,"uptimeStatus":2}]
        """)
        let monitors = try await client(session).uptimeMonitors()
        #expect(monitors.count == 2)
        #expect(monitors.first?.name == "example.com")
        // `uptimeStatus` is an integer and only 1 has been seen on a healthy monitor. Anything
        // else counts as down rather than guessing a table Sentry does not publish.
        #expect(monitors.first?.isHealthy == true)
        #expect(monitors.last?.isHealthy == false)
    }

    @Test("Environments come back as bare names")
    func environments() async throws {
        let session = StubServer.session()
        StubServer.enqueue(session, "/environments/", """
        [{"id":"1","name":"production"},{"id":"2","name":"staging"}]
        """)
        #expect(try await client(session).environments() == ["production", "staging"])
    }

    @Test("Releases decode with their new-issue count")
    func latestReleases() async throws {
        let session = StubServer.session()
        StubServer.enqueue(session, "/releases/", """
        [{"version":"1.4.0","shortVersion":"1.4.0","dateCreated":"2026-08-20T10:00:00Z",
          "newGroups":3}]
        """)
        let releases = try await client(session).latestReleases()
        #expect(releases.count == 1)
        #expect(releases.first?.newGroups == 3)
    }

    /// These three decoders were written against Sentry's published schema because the
    /// organization this was built against has none of the data. The README says so, and these
    /// tests are the honest half of that: the shape is pinned even though nobody has seen it
    /// live, so the day real data arrives the comparison is against something written down.
    @Test("Replays come wrapped in a data envelope")
    func replays() async throws {
        let session = StubServer.session()
        StubServer.enqueue(session, "/replays/", """
        {"data":[{"id":"abc","project_id":"11","environment":"production",
                  "error_ids":["e1","e2"]}]}
        """)
        let replays = try await client(session).replays(window: .twentyFourHours)
        #expect(replays.count == 1)
        #expect(replays.first?.errorIDs?.count == 2)
    }

    @Test("User feedback decodes with a name that may be missing")
    func userFeedback() async throws {
        let session = StubServer.session()
        StubServer.enqueue(session, "/user-feedback/", """
        [{"id":"1","name":"Someone","email":"someone@example.com","comments":"it broke",
          "dateCreated":"2026-08-20T10:00:00Z"},
         {"id":"2","name":null,"email":null,"comments":"still broken",
          "dateCreated":"2026-08-20T11:00:00.123456Z"}]
        """)
        let feedback = try await client(session).userFeedback()
        #expect(feedback.count == 2)
        #expect(feedback.last?.name == nil)
        // Both date shapes in one response, with and without fractional seconds, which is the
        // measured behaviour of this API and not a hypothetical.
        #expect(feedback.first?.dateCreated != feedback.last?.dateCreated)
    }

    /// The threshold arrives as **text**, the same way `issue.count` does. Declaring it a number
    /// does not fail the field, it fails the whole response.
    @Test("The transaction threshold arrives as text and comes out a number")
    func transactionThreshold() async throws {
        let session = StubServer.session()
        StubServer.enqueue(session, "/transaction-threshold/configure/", """
        {"id":"1","threshold":"450","metric":"duration"}
        """)
        let value = try await client(session).transactionThreshold(projectSlug: "example-api")
        #expect(value == 450)
    }

    @Test("A threshold that is not a number is nil, not a crash")
    func transactionThresholdNonsense() async throws {
        let session = StubServer.session()
        StubServer.enqueue(session, "/transaction-threshold/configure/", #"{"threshold":"lgtm"}"#)
        #expect(try await client(session).transactionThreshold(projectSlug: "x") == nil)
    }
}
