import Foundation
import Testing

@testable import CentinelaCore

// These are the project's integration tests: they exercise the FULL sign-in flow against a stub
// server, waiting and retrying included.
//
// A real `XCUITest` is not possible here: XCUITest ships with Xcode and this project is built
// with the standalone toolchain. Intercepting the transport at the `URLProtocol` level is as far
// as you get without Xcode, and it covers what can actually go wrong: the order of the steps,
// the four RFC 8628 errors, and refresh-token rotation.
@Suite("Device flow (OAuth 2.0, RFC 8628)")
struct DeviceFlowTests {
    /// Each test gets a fresh session, and with it its own response queue. That is why neither
    /// `.serialized` nor cleanup between tests is needed.
    private func flow(_ session: URLSession) -> DeviceFlow {
        DeviceFlow(
            host: URL(string: "https://sentry.example")!,
            clientID: "test-client",
            session: session
        )
    }

    private let okCode = """
    {"device_code":"DEV-1","user_code":"ABCD-EFGH",
     "verification_uri":"https://sentry.example/oauth/device/",
     "verification_uri_complete":"https://sentry.example/oauth/device/?user_code=ABCD-EFGH",
     "expires_in":600,"interval":5}
    """

    // MARK: - The steps

    @Test("Requesting the code returns what has to be shown to the person")
    func requestCode() async throws {
        let session = StubServer.session()
        StubServer.enqueue(session, "/oauth/device/code/", okCode)

        let code = try await flow(session).requestCode()
        #expect(code.userCode == "ABCD-EFGH")
        #expect(code.deviceCode == "DEV-1")
        #expect(code.completeURL?.absoluteString.contains("ABCD-EFGH") == true)
        #expect(code.interval == 5)

        // The requested scopes are part of the contract with the user: if someone adds
        // `project:write` here, Sentry's approval dialog asks for it and this test goes red.
        // The colons are not escaped (they are legal in a query) and the space goes as `%20`,
        // which Django accepts just like `+`.
        let sent = try #require(StubServer.requests(session).first?.body)
        #expect(sent.contains("scope=org:read%20project:read%20event:read"))
        #expect(!sent.contains("write"))
    }

    @Test("It waits while the person has not approved, and returns the token once they do")
    func waitAndApprove() async throws {
        let session = StubServer.session()
        StubServer.enqueue(session, "/oauth/token/", #"{"error":"authorization_pending"}"#, status: 400)
        StubServer.enqueue(session, "/oauth/token/", #"{"error":"authorization_pending"}"#, status: 400)
        let approved = #"{"access_token":"AT-1","refresh_token":"RT-1","expires_in":3600}"#
        StubServer.enqueue(session, "/oauth/token/", approved)

        let code = DeviceFlow.Code(
            deviceCode: "DEV-1", userCode: "X", verificationURL: URL(string: "https://x")!,
            completeURL: nil, expiresIn: 600, interval: 5
        )
        let recorder = SleepRecorder()
        let grant = try await flow(session).waitForApproval(code) { recorder.record($0) }

        #expect(grant.accessToken == "AT-1")
        #expect(grant.refreshToken == "RT-1")
        #expect(recorder.recorded == [5, 5, 5])
    }

    /// RFC 8628 requires raising the interval by 5 seconds each time `slow_down` arrives.
    /// Ignoring it leaves the client asking at the same rate and the server keeps refusing.
    @Test("`slow_down` raises the interval instead of getting stuck")
    func slowDown() async throws {
        let session = StubServer.session()
        StubServer.enqueue(session, "/oauth/token/", #"{"error":"slow_down"}"#, status: 400)
        StubServer.enqueue(session, "/oauth/token/", #"{"error":"slow_down"}"#, status: 400)
        StubServer.enqueue(session, "/oauth/token/", #"{"access_token":"AT","expires_in":60}"#)

        let code = DeviceFlow.Code(
            deviceCode: "D", userCode: "X", verificationURL: URL(string: "https://x")!,
            completeURL: nil, expiresIn: 600, interval: 5
        )
        let recorder = SleepRecorder()
        _ = try await flow(session).waitForApproval(code) { recorder.record($0) }
        #expect(recorder.recorded == [5, 10, 15])
    }

    @Test("The two bad endings of the RFC arrive as distinct errors", arguments: [
        (#"{"error":"access_denied"}"#, DeviceFlow.Failure.deniedByUser),
        (#"{"error":"expired_token"}"#, DeviceFlow.Failure.codeExpired)
    ])
    func badEndings(body: String, expected: DeviceFlow.Failure) async {
        let session = StubServer.session()
        // 400, which is what sentry.io actually returns for the RFC errors. With 200 the test
        // would pass even if the client threw on any non-2xx, which is a reasonable refactor
        // and would break the whole flow.
        StubServer.enqueue(session, "/oauth/token/", body, status: 400)

        let code = DeviceFlow.Code(
            deviceCode: "D", userCode: "X", verificationURL: URL(string: "https://x")!,
            completeURL: nil, expiresIn: 600, interval: 1
        )
        await #expect(throws: expected) {
            _ = try await flow(session).waitForApproval(code) { _ in }
        }
    }

    /// Sentry rotates the refresh token, but does not always send a new one. Storing `nil`
    /// blindly signs the user out on the next renewal, and they have to sign in again without
    /// understanding why.
    @Test("Refreshing without a new token keeps the old one")
    func refreshKeepsToken() async throws {
        let session = StubServer.session()
        StubServer.enqueue(session, "/oauth/token/", #"{"access_token":"AT-2","expires_in":3600}"#)

        let grant = try await flow(session).refresh("RT-OLD")
        #expect(grant.accessToken == "AT-2")
        #expect(grant.refreshToken == "RT-OLD")
    }

    @Test("Refreshing with a new token keeps the new one")
    func refreshRotates() async throws {
        let session = StubServer.session()
        let body = #"{"access_token":"AT-2","refresh_token":"RT-NEW","expires_in":3600}"#
        StubServer.enqueue(session, "/oauth/token/", body)

        let grant = try await flow(session).refresh("RT-OLD")
        #expect(grant.refreshToken == "RT-NEW")
    }

    /// An instance older than Sentry 26.1.0 does not have the endpoint. A 404 has to read as
    /// "this server does not support the flow", not as a generic error: the way out for the user
    /// is different (paste a token by hand).
    @Test("A 404 translates to «this server does not support the flow»")
    func oldServer() async {
        let session = StubServer.session()
        StubServer.enqueue(session, "/oauth/device/code/", #"{"detail":"not found"}"#, status: 404)

        await #expect(throws: DeviceFlow.Failure.serverDoesNotSupportFlow) {
            _ = try await flow(session).requestCode()
        }
    }

    /// Sentry's routes end in a slash and do NOT redirect when it is missing: they return a flat
    /// 404 (measured against sentry.io). If someone "cleans up" the trailing slashes the whole
    /// app stops working with an error that says nothing about slashes.
    @Test("The routes keep their trailing slash")
    func trailingSlash() async throws {
        let session = StubServer.session()
        StubServer.enqueue(session, "/oauth/device/code/", okCode)
        _ = try await flow(session).requestCode()
        let url = try #require(StubServer.requests(session).first?.path)
        #expect(url.hasSuffix("/oauth/device/code/"))
    }

    @Test("Without a client id it does not even go to the network")
    func noClientID() async {
        let session = StubServer.session()
        let noID = DeviceFlow(host: URL(string: "https://x")!, clientID: "", session: session)
        await #expect(throws: DeviceFlow.Failure.clientNotConfigured) {
            _ = try await noID.requestCode()
        }
        #expect(StubServer.requests(session).isEmpty)
    }

    @Test("It renews below 10% of remaining life, not before")
    func whenToRefresh() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let life: TimeInterval = 3600
        #expect(!DeviceFlow.shouldRefresh(expiresAt: now.addingTimeInterval(600), life: life, now: now))
        #expect(DeviceFlow.shouldRefresh(expiresAt: now.addingTimeInterval(300), life: life, now: now))
        #expect(DeviceFlow.shouldRefresh(expiresAt: now.addingTimeInterval(-1), life: life, now: now))
    }
}
