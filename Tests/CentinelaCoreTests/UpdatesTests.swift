import Foundation
import Testing

@testable import CentinelaCore

@Suite("Version comparison")
struct VersionTests {
    typealias Ver = UpdateChecker.Version

    @Test("It reads with and without the leading v")
    func withAndWithoutV() throws {
        #expect(try #require(Ver("v1.2.3")).parts == [1, 2, 3])
        #expect(try #require(Ver("1.2.3")).parts == [1, 2, 3])
    }

    /// The classic mistake of comparing versions as strings: "1.10" < "1.9" alphabetically, and
    /// the update is never offered from the tenth on.
    @Test("1.10 is greater than 1.9, not smaller")
    func tenthVersion() throws {
        #expect(try #require(Ver("1.9")) < #require(Ver("1.10")))
        #expect(try #require(Ver("0.9.0")) < #require(Ver("0.10.0")))
    }

    @Test("Zero padding: 1.2 and 1.2.0 are the same")
    func zeroPadding() throws {
        #expect(try !(#require(Ver("1.2")) < #require(Ver("1.2.0"))))
        #expect(try !(#require(Ver("1.2.0")) < #require(Ver("1.2"))))
    }

    @Test("A pre-release suffix does not break parsing")
    func prerelease() throws {
        #expect(try #require(Ver("v2.0.0-beta.3")).parts == [2, 0, 0])
    }

    @Test("Anything with no digits is not a version")
    func junk() {
        #expect(Ver("") == nil)
        #expect(Ver("v") == nil)
        #expect(Ver("latest") == nil)
    }

    @Test("It sorts a list the way you would expect")
    func sorting() throws {
        let versions = try ["1.0.0", "0.9.9", "1.10.0", "1.2.0", "2.0.0"].map { try #require(Ver($0)) }
        #expect(versions.sorted().map(\.description) == ["0.9.9", "1.0.0", "1.2.0", "1.10.0", "2.0.0"])
    }
}

/// The update check talks to GitHub's API. These tests exercise it against a stub server,
/// including the case that happens in this repository today: with no releases published,
/// `releases/latest` returns 404 (verified against api.github.com).
@Suite("Update check")
struct UpdateCheckTests {
    private func checker(_ session: URLSession) -> UpdateChecker {
        UpdateChecker(repository: "someone/something", session: session)
    }

    @Test("With no releases published (404) it does not invent an update")
    func noReleases() async {
        let session = StubServer.session()
        StubServer.enqueue(session, "/releases/latest", #"{"message":"Not Found"}"#, status: 404)
        #expect(await checker(session).check(currentVersion: "1.0.0") == nil)
    }

    @Test("A greater version is an update")
    func hasUpdate() async throws {
        let session = StubServer.session()
        StubServer.enqueue(session, "/releases/latest", #"""
        {"tag_name":"v1.2.0","html_url":"https://github.com/someone/something/releases/tag/v1.2.0"}
        """#)
        let update = try #require(await checker(session).check(currentVersion: "1.1.9"))
        #expect(update.version.description == "1.2.0")
    }

    @Test("The same version is not an update")
    func upToDate() async {
        let session = StubServer.session()
        StubServer.enqueue(session, "/releases/latest", #"{"tag_name":"v1.2.0","html_url":"https://x/y"}"#)
        #expect(await checker(session).check(currentVersion: "1.2.0") == nil)
    }

    /// Publishing a draft or a pre-release should not push anyone to update.
    @Test("Drafts and pre-releases do not count", arguments: ["draft", "prerelease"])
    func drafts(field: String) async {
        let session = StubServer.session()
        let body = #"{"tag_name":"v9.0.0","html_url":"https://x/y","\#(field)":true}"#
        StubServer.enqueue(session, "/releases/latest", body)
        #expect(await checker(session).check(currentVersion: "1.0.0") == nil)
    }
}
