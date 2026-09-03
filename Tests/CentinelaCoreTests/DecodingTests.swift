import Foundation
import Testing

@testable import CentinelaCore

/// Every test here pins a REAL shape of a Sentry response that already broke something, or that
/// would break if someone "simplified" the decoder. The fixtures are anonymized: real issue
/// titles carry URLs and business data, and this repository is public.
///
/// Swift Testing is used instead of XCTest for two reasons pointing the same way: it is the
/// default since 2026, and `XCTest` **does not ship** with a swiftly toolchain — only with
/// Xcode — so with XCTest the suite would not run on a machine without Xcode, which is exactly
/// the workflow this project documents.
@Suite("Decoding Sentry responses")
struct DecodingTests {
    private func fixture(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
            "missing fixture \(name).json"
        )
        return try Data(contentsOf: url)
    }

    /// Sentry sends the event count as text (`"13"`) and the user count as a number. Declaring
    /// `count` as `Int` makes the WHOLE array fail with `typeMismatch`, not just that field.
    @Test("The count arrives as text and decodes as a number")
    func countAsText() throws {
        let data = try fixture("issues")
        let issues = try SentryClient.decoder.decode([SentryIssue].self, from: data)
        #expect(issues.count == 2)
        #expect(issues[0].count == 13)
        #expect(issues[0].userCount == 3)
    }

    /// Two ISO-8601 formats in the same response: one with fractional seconds and one without.
    /// Plain `.iso8601` fails on the first; `.withFractionalSeconds` fails on the second.
    @Test("Dates with and without fractional seconds coexist")
    func twoDateFormats() throws {
        let data = try fixture("issues")
        let issues = try SentryClient.decoder.decode([SentryIssue].self, from: data)
        #expect(issues[0].lastSeen.timeIntervalSince1970 == 1_787_422_196)
        // `.123` and not `.123456`: `ISO8601DateFormatter` with `.withFractionalSeconds`
        // truncates to milliseconds, and Sentry sends microseconds. It makes no difference for
        // what this app does (sorting and showing "3 minutes ago") but whoever compares dates
        // to the microsecond against the API will wonder where they went.
        #expect(abs(issues[1].lastSeen.timeIntervalSince1970 - 1_787_418_000.123456) < 0.001)

        let releaseData = try fixture("releases")
        let releases = try SentryClient.decoder.decode([Release].self, from: releaseData)
        #expect(releases.count == 2)
    }

    @Test("A backend transaction splits into method and path; a page load has neither")
    func transactionMethod() {
        let post = TransactionStat(transaction: "POST /api/orpc/roles/rpc/syncPermissions", count: 2, p95: 3780)
        #expect(post.method == "POST")
        #expect(post.path == "/api/orpc/roles/rpc/syncPermissions")

        let page = TransactionStat(transaction: "/finanzas/cash-flow", count: 350, p95: 4270)
        #expect(page.method == nil)
        #expect(page.path == "/finanzas/cash-flow")

        // A first word that only looks method-ish is not one: the badge is for real HTTP verbs.
        let weird = TransactionStat(transaction: "GETSTARTED /x", count: 1, p95: 1)
        #expect(weird.method == nil)
        #expect(weird.path == "GETSTARTED /x")
    }

    @Test("Missing optional fields do not take down the list")
    func missingOptionals() throws {
        let data = try fixture("issues")
        let issues = try SentryClient.decoder.decode([SentryIssue].self, from: data)
        #expect(issues[1].culprit == nil)
        #expect(issues[1].substatus == nil)
        #expect(issues[1].isUnhandled == nil)
    }

    /// `events-stats` returns heterogeneous pairs `[epoch, [{"count": n}]]`, which are not an
    /// object and therefore have no synthesizable `Codable`. The fourth point carries an empty
    /// bucket list, which is what arrives when there were no events in that interval.
    @Test("The event series comes from heterogeneous pairs")
    func eventSeries() throws {
        let series = try EventSeries(json: fixture("events-stats"))
        #expect(series.points.map(\.count) == [0, 1, 4, 0])
        #expect(series.total == 5)
        #expect(series.points[0].time.timeIntervalSince1970 == 1_787_335_200)
    }

    @Test("A response without `data` fails loudly instead of returning an empty series")
    func seriesWithoutData() {
        #expect(throws: SentryError.self) {
            try EventSeries(json: Data(#"{"meta": {}}"#.utf8))
        }
    }

    @Test("The uptime status is an integer, not a boolean")
    func uptimeIsInteger() throws {
        let data = try fixture("uptime")
        let monitors = try SentryClient.decoder.decode([UptimeMonitor].self, from: data)
        #expect(monitors[0].isHealthy)
        #expect(!monitors[1].isHealthy)
        let allActive = monitors.allSatisfy(\.isActive)
        #expect(allActive)
    }

    /// When a release is named after a commit, the API repeats the 40-character SHA in
    /// `shortVersion`, so shortening is on us. A semantic version is left alone.
    @Test("A SHA is shortened and a semantic version is not")
    func releaseLabel() throws {
        let data = try fixture("releases")
        let releases = try SentryClient.decoder.decode([Release].self, from: data)
        #expect(releases[0].label == "fa907c0")
        #expect(releases[1].label == "v2.4.1")
        // The projects a release went to, when the response carries them. Embedded in a release,
        // Sentry sends the project id as a NUMBER (unlike `/projects/`, which sends a string), so
        // this also pins that the lenient `Project` decoder turns it back into the string id.
        #expect(releases[0].primaryProjectSlug == "example-api")
        #expect(releases[0].projects?.first?.id == "4511380596523008")
        #expect(releases[1].primaryProjectSlug == "example-web")
    }

    /// Some pipelines name a release by an ISO-8601 timestamp; shown raw it is a wall of
    /// punctuation, so `label` reformats it to a short date. Asserted by what it is NOT (no `T`,
    /// no `Z`) so the check does not pin a locale-specific rendering.
    @Test("A release named by an ISO timestamp shows as a date, not raw punctuation")
    func releaseTimestampLabel() throws {
        let json = """
        [{"version":"2026-09-03T01:07:11Z","shortVersion":"2026-09-03T01:07:11Z",
          "dateCreated":"2026-09-03T01:07:11Z","newGroups":0}]
        """
        let releases = try SentryClient.decoder.decode([Release].self, from: Data(json.utf8))
        #expect(!releases[0].label.contains("T"))
        #expect(!releases[0].label.contains("Z"))
        #expect(releases[0].label != releases[0].shortVersion)
    }

    @Test("An unknown level does not break and falls back to error", arguments: [
        ("warning", Severity.warning),
        ("fatal", Severity.fatal),
        ("something-sentry-invents-tomorrow", Severity.error)
    ])
    func unknownLevel(text: String, expected: Severity) {
        #expect(Severity(sentryLevel: text) == expected)
    }

    @Test("A missing level also falls back to error")
    func missingLevel() {
        #expect(Severity(sentryLevel: nil) == .error)
    }
}

/// Sentry publishes a deprecation policy through headers. An app that ignores them finds out
/// about the change on the day it stops working.
@Suite("Sentry deprecation policy")
struct DeprecationTests {
    // The URL is hoisted to a constant: nesting a `#require` inside another makes the compiler
    // blow up with "recursive expansion of macro".
    private static let url = URL(string: "https://sentry.io/api/0/organizations/x/issues/")

    private func response(_ fields: [String: String]) throws -> HTTPURLResponse {
        let url = try #require(Self.url)
        return try #require(HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: fields
        ))
    }

    @Test("Without the headers there is no notice")
    func noNotice() throws {
        let http = try response(["Content-Type": "application/json"])
        #expect(SentryClient.deprecation(in: http, path: "issues") == nil)
    }

    @Test("With a date and a replacement the notice is complete")
    func fullNotice() throws {
        let http = try response([
            "X-Sentry-Deprecation-Date": "2027-01-01",
            "X-Sentry-Replacement-Endpoint": "/organizations/{org}/something-else/"
        ])
        let notice = try #require(SentryClient.deprecation(in: http, path: "issues"))
        #expect(notice.date == "2027-01-01")
        #expect(notice.replacement == "/organizations/{org}/something-else/")
    }

    /// The replacement is optional in the policy: some routes are retired with no successor.
    /// Requiring it would make the most important notice, the one with no way out, the only one
    /// nobody sees.
    @Test("A date with no replacement still raises a notice")
    func noticeWithoutReplacement() throws {
        let http = try response(["X-Sentry-Deprecation-Date": "2027-01-01"])
        let notice = try #require(SentryClient.deprecation(in: http, path: "uptime"))
        #expect(notice.replacement == nil)
    }
}

/// The device flow hands back a token and nothing else. To end up configured, the app has to ask
/// Sentry which organizations that token reaches.
@Suite("Organizations")
struct OrganizationsTests {
    private func client(_ session: URLSession, organization: String = "") -> SentryClient {
        SentryClient(
            credentials: Credentials(
                token: "test-token", organization: organization,
                host: URL(string: "https://sentry.example")!
            ),
            session: session
        )
    }

    /// The route carries NO organization prefix: asking for it with one gives a 404, and this is
    /// exactly the endpoint used when the organization is not known yet.
    @Test("It hits /api/0/organizations/, with no organization prefix")
    func pathWithoutPrefix() async throws {
        let session = StubServer.session()
        StubServer.enqueue(session, "/api/0/organizations/", "[]")
        _ = try await client(session).organizations()
        let asked = try #require(StubServer.requests(session).first?.path)
        #expect(asked.hasSuffix("/api/0/organizations/"))
        #expect(!asked.contains("/organizations//"))
    }

    @Test("Slug and name decode")
    func decodes() async throws {
        let session = StubServer.session()
        let body = #"[{"id":"1","slug":"example","name":"Example Inc"}]"#
        StubServer.enqueue(session, "/api/0/organizations/", body)
        let organizations = try await client(session).organizations()
        #expect(organizations.map(\.slug) == ["example"])
        #expect(organizations[0].name == "Example Inc")
    }

    /// Without a token nothing goes to the network. Without an organization it does, which is
    /// the difference between this route and every other one.
    @Test("No token fails before asking; no organization does not")
    func minimumCredentials() async {
        let session = StubServer.session()
        let noToken = SentryClient(
            credentials: Credentials(token: "", organization: "", host: URL(string: "https://x")!),
            session: session
        )
        await #expect(throws: SentryError.self) { _ = try await noToken.organizations() }
        #expect(StubServer.requests(session).isEmpty)
    }
}

/// Sentry's triage, which is a different question from the event level: a `warning` that keeps
/// escalating outranks a one-off `error`. It arrives as `priority` and used to be decoded and
/// thrown away.
@Suite("Triage")
struct TriageTests {
    @Test("The three documented values map through", arguments: [
        ("high", Triage.high), ("medium", Triage.medium), ("low", Triage.low)
    ])
    func knownValues(text: String, expected: Triage) {
        #expect(Triage(sentryPriority: text) == expected)
    }

    /// Unknown or missing reads as medium and not as an error: this drives a colour, not a
    /// contract, and a value Sentry adds next year should not make a row unreadable.
    @Test("Anything else reads as medium")
    func unknownValue() {
        #expect(Triage(sentryPriority: "whatever-comes-next") == .medium)
        #expect(Triage(sentryPriority: nil) == .medium)
    }

    @Test("An issue exposes its triage from the decoded payload")
    func fromPayload() throws {
        let json = #"""
        [{"id":"1","shortId":"EX-1","title":"t","level":"warning","priority":"high",
          "permalink":"https://example.sentry.io/issues/1/","lastSeen":"2026-08-22T18:09:56Z",
          "userCount":0,"count":"1","project":{"id":"1","slug":"s","name":"n"}}]
        """#
        let issues = try SentryClient.decoder.decode([SentryIssue].self, from: Data(json.utf8))
        #expect(issues[0].triage == .high)
        #expect(issues[0].severity == .warning, "triage and level are separate signals")
    }
}
