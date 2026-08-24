import Foundation

@testable import CentinelaCore

/// A response queued in the stub server.
struct StubResponse {
    let path: String
    let status: Int
    let body: String
    /// Extra headers. Sentry says things in headers that change behaviour — `Retry-After` on a
    /// 429, and the deprecation pair — so a stub that could only carry a body could not test
    /// any of it.
    var headers: [String: String] = [:]
}

/// Records how long each polling round slept.
///
/// It is a class with a lock rather than a `var` captured by the closure: `sleep` is
/// `@Sendable`, so mutating a local from inside is a race. Today it is a warning because the
/// package is in language mode 5; in mode 6 it is an error, and the test would have to be
/// rewritten anyway.
final class SleepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [TimeInterval] = []

    func record(_ seconds: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        values.append(seconds)
    }

    var recorded: [TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

/// Stub HTTP server, shared by the suites that exercise the transport: the device flow and the
/// update checker.
///
/// **Each session has its own queue**, keyed by a header the configuration injects into every
/// request. The first version kept a single global queue plus `.serialized` on each suite: that
/// was not enough, because the trait serializes WITHIN a suite and not between suites, so two
/// suites running in parallel stole each other's responses and failed with "no queued response",
/// which says nothing about the real problem.
final class StubServer: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var queues: [String: [StubResponse]] = [:]
    nonisolated(unsafe) private static var seen: [String: [(path: String, body: String)]] = [:]
    nonisolated(unsafe) private static var nextID = 0

    static let sessionHeader = "X-Stub-Server"

    /// A session with a queue of its own. It goes away with the test that created it.
    static func session() -> URLSession {
        lock.lock()
        nextID += 1
        let identifier = "session-\(nextID)"
        queues[identifier] = []
        seen[identifier] = []
        lock.unlock()

        let conf = URLSessionConfiguration.ephemeral
        conf.protocolClasses = [StubServer.self]
        conf.httpAdditionalHeaders = [sessionHeader: identifier]
        return URLSession(configuration: conf)
    }

    static func enqueue(
        _ session: URLSession, _ path: String, _ body: String,
        status: Int = 200, headers: [String: String] = [:]
    ) {
        guard let identifier = identifier(of: session) else { return }
        lock.lock()
        defer { lock.unlock() }
        queues[identifier, default: []].append(
            StubResponse(path: path, status: status, body: body, headers: headers))
    }

    static func requests(_ session: URLSession) -> [(path: String, body: String)] {
        guard let identifier = identifier(of: session) else { return [] }
        lock.lock()
        defer { lock.unlock() }
        return seen[identifier] ?? []
    }

    private static func identifier(of session: URLSession) -> String? {
        session.configuration.httpAdditionalHeaders?[sessionHeader] as? String
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        // `URL.path` DROPS the trailing slash, and Sentry's routes carry one
        // (`/oauth/device/code/`). Matching on `path` made nothing line up.
        let path = request.url?.absoluteString ?? ""
        let identifier = request.value(forHTTPHeaderField: StubServer.sessionHeader) ?? ""
        let sentBody = StubServer.body(of: request)

        StubServer.lock.lock()
        StubServer.seen[identifier, default: []].append((path, sentBody))
        let index = StubServer.queues[identifier]?.firstIndex { path.contains($0.path) }
        let chosen = index.map { StubServer.queues[identifier]!.remove(at: $0) }
            ?? StubResponse(path: path, status: 500, body: #"{"error":"no queued response"}"#)
        StubServer.lock.unlock()

        let http = HTTPURLResponse(
            url: request.url!, statusCode: chosen.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"].merging(chosen.headers) { _, stub in stub }
        )!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(chosen.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    /// `httpBody` comes back empty once URLSession has moved the body to a stream, which is what
    /// happens with form POSTs.
    private static func body(of request: URLRequest) -> String {
        if let data = request.httpBody { return String(bytes: data, encoding: .utf8) ?? "" }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return String(bytes: data, encoding: .utf8) ?? ""
    }
}

/// An in-memory `SecretStore`, shared because two suites had grown one each.
///
/// It counts reads and can refuse a write to one account. Both exist for a specific test — the
/// ordering in `shouldRefresh`, which changes no answer and only decides whether the Keychain is
/// touched, and the copy-before-delete in the migrations, which behaves identically to the wrong
/// version every time a write succeeds. A real Keychain will not fail on demand and does not
/// count, so neither could be tested through one.
final class InMemoryStore: SecretStore, @unchecked Sendable {
    private(set) var reads = 0
    var items: [String: String]
    let refusesWritesTo: String?

    init(_ items: [String: String] = [:], refusesWritesTo: String? = nil) {
        self.items = items
        self.refusesWritesTo = refusesWritesTo
    }

    func read(account: String) throws -> String? {
        reads += 1
        return items[account]
    }

    func save(_ value: String, account: String) throws {
        if account == refusesWritesTo { throw Keychain.Failure.system(-25299) }
        items[account] = value
    }

    func delete(account: String) throws { items[account] = nil }
}
