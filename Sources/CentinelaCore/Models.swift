import Foundation

// The fields here come from looking at real Sentry responses, not from the docs. The three
// surprising ones are commented where they bite.

public struct Project: Codable, Sendable, Hashable {
    public let id: String
    public let slug: String
    public let name: String
}

public struct Organization: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let slug: String
    public let name: String
}

/// A Sentry issue.
///
/// It is named `SentryIssue` and not `Issue` for a concrete reason: Swift Testing exports its
/// own `Testing.Issue`, and in any file that does `import Testing` the short name resolves to
/// theirs. The symptom tells you nothing — the compiler emits `failed to produce diagnostic for
/// expression` on the call to `decode`, never mentioning the ambiguity — and you lose a good
/// while looking for the bug inside `Codable`.
public struct SentryIssue: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let shortId: String
    public let title: String
    public let culprit: String?
    public let level: String?
    public let substatus: String?
    public let permalink: URL
    public let lastSeen: Date
    public let userCount: Int
    public let project: Project
    public let isUnhandled: Bool?

    /// Sentry returns the event count as **text** (`"13"`), not as a number, while `userCount`
    /// does arrive as an integer. Declaring it `Int` fails with `typeMismatch` and takes down
    /// the whole array, not just that field.
    public let count: Int

    enum CodingKeys: String, CodingKey {
        case id, shortId, title, culprit, level, substatus, permalink, lastSeen
        case userCount, project, isUnhandled, count
    }

    public init(from decoder: any Decoder) throws {
        let cont = try decoder.container(keyedBy: CodingKeys.self)
        id = try cont.decode(String.self, forKey: .id)
        shortId = try cont.decode(String.self, forKey: .shortId)
        title = try cont.decode(String.self, forKey: .title)
        culprit = try cont.decodeIfPresent(String.self, forKey: .culprit)
        level = try cont.decodeIfPresent(String.self, forKey: .level)
        substatus = try cont.decodeIfPresent(String.self, forKey: .substatus)
        permalink = try cont.decode(URL.self, forKey: .permalink)
        lastSeen = try cont.decode(Date.self, forKey: .lastSeen)
        userCount = try cont.decodeIfPresent(Int.self, forKey: .userCount) ?? 0
        project = try cont.decode(Project.self, forKey: .project)
        isUnhandled = try cont.decodeIfPresent(Bool.self, forKey: .isUnhandled)
        count = Int(try cont.decode(String.self, forKey: .count)) ?? 0
    }

    public func encode(to encoder: any Encoder) throws {
        var cont = encoder.container(keyedBy: CodingKeys.self)
        try cont.encode(id, forKey: .id)
        try cont.encode(shortId, forKey: .shortId)
        try cont.encode(title, forKey: .title)
        try cont.encodeIfPresent(culprit, forKey: .culprit)
        try cont.encodeIfPresent(level, forKey: .level)
        try cont.encodeIfPresent(substatus, forKey: .substatus)
        try cont.encode(permalink, forKey: .permalink)
        try cont.encode(lastSeen, forKey: .lastSeen)
        try cont.encode(userCount, forKey: .userCount)
        try cont.encode(project, forKey: .project)
        try cont.encodeIfPresent(isUnhandled, forKey: .isUnhandled)
        try cont.encode(String(count), forKey: .count)
    }

    public var severity: Severity { Severity(sentryLevel: level) }
}

public enum Severity: String, Sendable {
    case fatal, error, warning, info, debug, sample

    init(sentryLevel level: String?) {
        self = Severity(rawValue: level ?? "") ?? .error
    }

    /// SF Symbol name. `NSImage(systemSymbolName:)` returns `nil` for a name that does not
    /// exist, so only symbols present since macOS 11 are used.
    public var symbol: String {
        switch self {
        case .fatal: "flame.fill"
        case .error: "exclamationmark.triangle.fill"
        case .warning: "exclamationmark.circle.fill"
        case .info, .debug, .sample: "info.circle"
        }
    }
}

public struct Release: Codable, Sendable, Identifiable, Hashable {
    public let version: String
    public let shortVersion: String
    public let dateCreated: Date
    public let newGroups: Int

    public var id: String { version }

    /// When a release is named after a commit, the API repeats the full 40-character SHA in
    /// `shortVersion`, so shortening is on us.
    public var label: String {
        let text = shortVersion
        let looksLikeSHA = text.count == 40 && text.allSatisfy(\.isHexDigit)
        return looksLikeSHA ? String(text.prefix(7)) : text
    }
}

public struct UptimeMonitor: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let url: URL
    public let status: String
    public let intervalSeconds: Int

    /// An integer, not a string and not a boolean. Only `1` has been observed on a healthy
    /// monitor; anything else is treated as unhealthy rather than guessing the full table,
    /// which the API does not document.
    public let uptimeStatus: Int

    public var isHealthy: Bool { uptimeStatus == 1 }
    public var isActive: Bool { status == "active" }
}

/// Time series from `events-stats`. The response comes back as heterogeneous pairs
/// `[epoch, [{"count": n}]]`, which is not an object, so there is no synthesizable `Codable`.
public struct EventSeries: Sendable, Hashable {
    public struct Point: Sendable, Hashable {
        public let time: Date
        public let count: Int
    }

    public let points: [Point]

    public var total: Int { points.reduce(0) { $0 + $1.count } }

    public init(points: [Point]) { self.points = points }

    public init(json: Data) throws {
        guard
            let root = try JSONSerialization.jsonObject(with: json) as? [String: Any],
            let rows = root["data"] as? [[Any]]
        else { throw SentryError.unexpectedResponse("events-stats without a `data` array") }

        points = rows.compactMap { row in
            guard row.count >= 2, let epoch = row[0] as? TimeInterval else { return nil }
            let buckets = row[1] as? [[String: Any]] ?? []
            let count = buckets.reduce(0) { $0 + (($1["count"] as? NSNumber)?.intValue ?? 0) }
            return Point(time: Date(timeIntervalSince1970: epoch), count: count)
        }
    }
}
