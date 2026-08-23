import Foundation
import Testing

@testable import CentinelaCore

/// The spans route has no fixed schema: the response's keys are literally the `field=` parameters
/// that were requested. So the request and the parser have to agree, and these tests are what
/// keeps them agreeing.
@Suite("Slowest transactions")
struct PerformanceTests {
    private func fixture(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        )
        return try Data(contentsOf: url)
    }

    /// `count()` arrives as a JSON number (150.0), not an integer, even though `meta.fields`
    /// calls it an integer. Decoding it straight into `Int` fails. Measured against the real API.
    @Test("The count arrives as a float and lands as an integer")
    func countIsAFloat() throws {
        let rows = try TransactionStat.from(json: fixture("spans"))
        #expect(rows[0].count == 150)
        #expect(rows[0].p95 == 1170.06)
    }

    /// A row with no `transaction` is dropped rather than shown as an empty name. Sentry returns
    /// one when a span has no transaction attached.
    @Test("A row without a transaction name is dropped, not shown blank")
    func rowWithoutName() throws {
        let rows = try TransactionStat.from(json: fixture("spans"))
        #expect(rows.count == 3, "the fourth row has no transaction")
        #expect(rows.allSatisfy { !$0.transaction.isEmpty })
    }

    @Test("A payload without `data` fails loudly")
    func withoutData() {
        #expect(throws: SentryError.self) {
            _ = try TransactionStat.from(json: Data(#"{"meta":{}}"#.utf8))
        }
    }

    /// The guard that keeps request and parser in step: if someone changes the requested field
    /// without changing the key the parser reads, every row silently comes back as zero.
    @Test("The requested fields are the keys the parser reads")
    func fieldsMatchTheParser() async throws {
        let session = StubServer.session()
        StubServer.enqueue(session, "/events/", #"{"data":[]}"#)
        let api = SentryClient(
            credentials: Credentials(token: "t", organization: "x", host: URL(string: "https://s.test")!),
            session: session
        )
        _ = try await api.slowestTransactions(window: .twentyFourHours)
        let asked = try #require(StubServer.requests(session).first?.path).removingPercentEncoding
        #expect(asked?.contains("field=\(TransactionStat.countField)") == true)
        #expect(asked?.contains("field=\(TransactionStat.p95Field)") == true)
        #expect(asked?.contains("dataset=spans") == true)
    }
}
