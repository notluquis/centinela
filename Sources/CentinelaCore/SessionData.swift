import Foundation

/// Everything the app knows because a particular Sentry session told it so.
///
/// It is one value rather than eighteen properties for exactly one reason: signing out has to
/// forget all of it, and a hand-written list of eighteen assignments is wrong the first time
/// somebody adds a nineteenth field and does not think of it. That is not hypothetical. It
/// shipped: the menu bar kept counting 539 errors from an account the app no longer reached,
/// above a panel that already said "Not configured yet", because the early return that was
/// supposed to clear things cleared nothing at all.
///
/// Resetting is `data = SessionData()`. There is no test for that and there should not be: a
/// test would assert what the type already makes true. The fix is the construction, not a check
/// bolted on beside it.
///
/// `lastUpdated` is deliberately **not** in here. It outlives a session on purpose — after a
/// restart the panel says how old the data on screen is — so it is persisted, and a persisted
/// value does not belong in a struct whose whole job is to be thrown away.
public struct SessionData: Sendable {
    public var series: EventSeries = .init(points: [])
    public var monitors: [UptimeMonitor] = []
    public var issues: [SentryIssue] = []
    public var forReview: [SentryIssue] = []
    public var escalating: [SentryIssue] = []
    public var regressed: [SentryIssue] = []
    public var releases: [Release] = []
    public var crons: [CronMonitor] = []
    public var crashFree: Double?
    public var errorsByProject: [ProjectErrorCount] = []
    public var environments: [String] = []
    public var transactions: [TransactionStat] = []

    /// Sentry's own threshold for the selected project, in milliseconds. 300 is what Sentry
    /// itself returns by default, so it is the fallback when no single project is selected.
    public var transactionThreshold: Double = 300
    public var replays: [Replay] = []
    public var feedback: [UserFeedback] = []

    public var lastError: String?
    public var tokenTooPowerful = false
    public var deprecation: DeprecationNotice?

    public init() {}
}
