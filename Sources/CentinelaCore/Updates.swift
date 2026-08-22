import Foundation

/// New-version notice, read from GitHub's releases API.
///
/// **Why not Sparkle**, which is what Stats and TheBoringNotch use: its own sandboxing
/// documentation says ad-hoc distributions are "not ideal for distribution" and have to be
/// re-signed with a real certificate. Sparkle also wants `Installer.xpc` embedded,
/// `SUEnableInstallerLauncherService` turned on, and two temporary `mach-lookup` exceptions in
/// the entitlements. All of that to install a binary that Gatekeeper would reject anyway for
/// being ad-hoc signed.
///
/// This tells you and opens the page. You download and replace. No XPC, no sandbox exceptions,
/// no 99-dollars-a-year certificate.
public struct UpdateChecker: Sendable {
    public struct Version: Sendable, Equatable, Comparable, CustomStringConvertible {
        public let parts: [Int]

        /// Accepts `v1.2.3`, `1.2.3`, `1.2` and `1`. Anything non-numeric is dropped, so
        /// `1.2.3-beta.1` reads as `1.2.3`: to decide "is there something newer" that is
        /// enough, and ordering pre-release precedence is a problem this project does not have.
        public init?(_ text: String) {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
                .drop { $0 == "v" || $0 == "V" }
            let numbers = trimmed
                .prefix { $0.isNumber || $0 == "." }
                .split(separator: ".")
                .compactMap { Int($0) }
            guard !numbers.isEmpty else { return nil }
            parts = numbers
        }

        public static func < (lhs: Version, rhs: Version) -> Bool {
            // Compared with zero padding: `1.2` and `1.2.0` are the same version, and `1.10` is
            // greater than `1.9`. Comparing the strings would say the opposite.
            let length = max(lhs.parts.count, rhs.parts.count)
            for index in 0..<length {
                let one = index < lhs.parts.count ? lhs.parts[index] : 0
                let other = index < rhs.parts.count ? rhs.parts[index] : 0
                if one != other { return one < other }
            }
            return false
        }

        public var description: String { parts.map(String.init).joined(separator: ".") }
    }

    public struct Update: Sendable, Equatable {
        public let version: Version
        public let page: URL
    }

    private let repository: String
    private let session: URLSession

    public init(repository: String, session: URLSession = .shared) {
        self.repository = repository
        self.session = session
    }

    /// Returns the update when there is one, or `nil` when you are already current.
    ///
    /// A network failure returns `nil` rather than throwing: failing to find an update is not
    /// an error anyone cares about, and turning it into a red banner in the panel trains people
    /// to ignore red banners.
    public func check(currentVersion: String) async -> Update? {
        guard let current = Version(currentVersion) else { return nil }

        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("centinela", forHTTPHeaderField: "User-Agent")

        guard
            let (data, response) = try? await session.data(for: request),
            let http = response as? HTTPURLResponse, http.statusCode == 200,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            // Drafts and pre-releases do not count: publishing a draft should not push anyone
            // to update.
            (json["draft"] as? Bool) != true,
            (json["prerelease"] as? Bool) != true,
            let tag = json["tag_name"] as? String,
            let latest = Version(tag),
            let page = (json["html_url"] as? String).flatMap(URL.init(string:))
        else { return nil }

        return latest > current ? Update(version: latest, page: page) : nil
    }
}
