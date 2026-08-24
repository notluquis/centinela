import AppKit
import CentinelaCore
import Observation
import SwiftUI

/// Every piece of state the UI observes, and the only place that decides WHEN the API is called.
///
/// The split is not cosmetic. `refreshCheap()` runs on every timer tick and asks for the two
/// routes measured as cheap (error series 378 ms / 937 B, uptime 490 ms). `refreshExpensive()`
/// asks for the issue list (1047 ms / 10.6 KB) and is only called when the panel opens. Sentry's
/// API exposes no ETag on any route, so there is no conditional revalidation to exploit: staying
/// light means asking for little, not asking cheaply.
@MainActor
@Observable
final class AppState {
    static let repository = "notluquis/centinela"

    /// Everything a Sentry session told us, as one value. Signing out is `data = SessionData()`
    /// rather than eighteen assignments somebody has to remember to keep in step.
    var data = SessionData()

    /// Owned here, not by the view that shows it.
    ///
    /// `AboutView` declared it as `@State private var updater = Updater()`, and a `@State`
    /// default is evaluated every time the struct is initialised — which is every pass of
    /// `SettingsView.body`, so on every change of query shape. Each discarded instance had
    /// already run `SPUStandardUpdaterController(startingUpdater: true)`, which schedules a check
    /// and can fire an appcast download. Sparkle's `dealloc` cleans up, so this was waste rather
    /// than a leak, but it was waste on a timer.
    let updater = Updater()

    /// Whether a request is in flight. This one is NOT session data: it describes the app, not
    /// the account, and `forgetSession()` has no business clearing it.
    var loading = false

    /// Persisted: after a restart the panel used to show nothing instead of saying how old the
    /// data on screen is. Not a secret, so `UserDefaults` rather than the Keychain.
    var lastUpdated: Date? {
        didSet {
            UserDefaults.standard.set(lastUpdated?.timeIntervalSince1970 ?? 0, forKey: "lastUpdated")
        }
    }

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var asleep = false

    var settings: AppSettings
    let login: LoginController

    // The parameter is optional rather than `= AppSettings()`: default values are evaluated in
    // a non-isolated context, and `AppSettings` is main-actor isolated. With the default inline
    // the compiler rejects the call (`#ActorIsolatedCall`).
    init(settings: AppSettings? = nil) {
        let resolved = settings ?? AppSettings()
        self.settings = resolved
        self.login = LoginController(settings: resolved)
        let saved = UserDefaults.standard.double(forKey: "lastUpdated")
        if saved > 0 { lastUpdated = Date(timeIntervalSince1970: saved) }
        observeSleep()
    }

    deinit {
        // `deinit` does not run on the main actor; the observers are removed without touching
        // anything else on `self`.
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers { center.removeObserver(observer) }
    }

    private var client: SentryClient? {
        guard let credentials = settings.credentials() else { return nil }
        return SentryClient(
            credentials: credentials,
            projectID: settings.selectedProjectID,
            environment: settings.selectedEnvironment
        ) { [weak self] notice in
            Task { @MainActor in self?.data.deprecation = notice }
        }
    }

    var installedVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    // MARK: - The cycle

    func start() {
        reschedule()
        Task { await refreshCheap() }
    }

    func reschedule() {
        timer?.invalidate()
        let every = settings.intervalSeconds
        let fresh = Timer(timeInterval: every, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshCheap() }
        }
        // Generous tolerance: it lets the system coalesce this wake-up with others instead of
        // pulling the CPU out of idle just for us. In an app that polls every few minutes,
        // second-level precision buys nothing and costs battery.
        fresh.tolerance = every * 0.2
        RunLoop.main.add(fresh, forMode: .common)
        timer = fresh
    }

    /// On sleep the timer stops, and on wake it refreshes immediately. Without this, `Timer`
    /// coalesces the missed fire and goes off on wake anyway, but with pre-sleep data on screen
    /// until the following cycle.
    private func observeSleep() {
        let center = NSWorkspace.shared.notificationCenter
        let onSleep = center.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.asleep = true
                self?.timer?.invalidate()
            }
        }
        let onWake = center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.asleep = false
                self?.reschedule()
                await self?.refreshCheap()
            }
        }
        observers.append(contentsOf: [onSleep, onWake])
    }

    // MARK: - Requests

    func refreshCheap() async {
        guard !asleep else { return }
        // Before asking for anything: if the OAuth token is about to expire, renew it. This
        // lives here rather than on its own timer because what matters is having a live token
        // right when it is about to be used, not having tried while the machine was asleep.
        if let refreshFailure = await login.refreshIfNeeded() {
            data.lastError = refreshFailure
        }
        // Not a plain `return`: leaving early without clearing is what kept a signed-out menu
        // bar counting the previous account's errors.
        guard let client else { forgetSession(); return }
        // Sentry's own `Retry-After`, honoured. It used to be read out of the header, put in an
        // error, printed as "Retrying in 30s" and then ignored: nothing retried and nothing
        // waited, so the app carried on asking on its own schedule, which is what that header
        // exists to stop.
        //
        // AFTER the guard above, not before it. Placed first, signing out while Sentry had the
        // app silenced would return before anything was cleared, and the menu bar would keep
        // counting the previous account's errors — which is the bug that guard was added for.
        guard !settings.isRateLimited else { return }
        loading = true
        defer { loading = false }
        do {
            // Cron monitors join the cheap cycle because a failing cron belongs in the menu bar
            // next to an outage, not behind a click. 349 ms measured, and it runs alongside the
            // other two rather than after them.
            async let series = client.errorSeries(window: settings.window)
            async let monitors = client.uptimeMonitors()
            async let crons = client.cronMonitors()
            data.series = try await series
            data.monitors = try await monitors
            data.crons = try await crons
            data.lastError = nil
            lastUpdated = .now
        } catch {
            note(error)
        }
    }

    func refreshExpensive() async {
        guard !settings.isRateLimited, let client else { return }
        loading = true
        defer { loading = false }
        do {
            async let issues = client.unresolvedIssues(window: settings.window, limit: settings.maxIssues)
            async let forReview = client.issuesForReview()
            async let escalating = client.escalatingIssues()
            async let regressed = client.regressedIssues()
            async let releases = client.latestReleases()
            async let crashFree = client.crashFreeRate(window: settings.window)
            async let byProject = client.errorsByProject(window: settings.window)
            data.issues = try await issues
            data.forReview = try await forReview
            data.escalating = try await escalating
            data.regressed = try await regressed
            data.releases = try await releases
            data.crashFree = try await crashFree
            data.errorsByProject = try await byProject

            // Performance and feedback go in their own step rather than the `async let` group
            // above: they are the two routes with no live data behind them here, so a failure
            // must not take down the lists that do work.
            data.transactions = (try? await client.slowestTransactions(window: settings.window)) ?? []
            // Only when a single project is selected: the threshold is a per-project setting and
            // there is no organization-wide one to ask for.
            if let slug = settings.selectedProjectID.flatMap({ id in
                data.errorsByProject.first { $0.projectID == id }?.slug
            }) {
                data.transactionThreshold = (try? await client.transactionThreshold(projectSlug: slug)) ?? 300
            }
            data.replays = (try? await client.replays(window: settings.window)) ?? []
            data.feedback = (try? await client.userFeedback()) ?? []
            data.lastError = nil
        } catch {
            note(error)
        }
    }

    func checkTokenPower() async {
        guard let client else { return }
        data.tokenTooPowerful = await !client.tokenLooksReadOnly()
    }

    // MARK: - What gets drawn up top

    /// Drops everything that belonged to the session that just ended.
    ///
    /// Without this, signing out left the last numbers on screen forever: `refreshCheap` bailed
    /// out at `guard let client` before touching anything, so the menu bar kept showing 539
    /// errors above a panel that said "Not configured yet". The data is not stale, it belongs to
    /// an account the app no longer has.
    ///
    /// Every field is listed by hand. That is the weak part: a field added later and not added
    /// here comes back to haunt the next sign-out, and `AppState` lives in the app target, which
    /// the suite cannot reach because it needs AppKit. Keep this next to the declarations.
    /// Drops everything that belonged to the session that just ended.
    ///
    /// One assignment, because `SessionData` is one value. It used to be eighteen by hand, which
    /// is how the menu bar ended up counting 539 errors from an account the app no longer
    /// reached, above a panel that already said "Not configured yet".
    ///
    /// `lastUpdated` is separate on purpose: it is persisted so the panel can say how old the
    /// data on screen is after a restart, and it is not part of a value whose job is to be
    /// thrown away.
    func forgetSession() {
        data = SessionData()
        lastUpdated = nil
    }

    /// Records what went wrong, and — when Sentry asked for silence — for how long.
    ///
    /// One place rather than one per `catch`, so a second call site cannot quietly forget the
    /// second half. Forgetting it is what this replaces.
    private func note(_ error: Error) {
        data.lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        if case SentryError.rateLimited(let wait) = error {
            // No header means Sentry did not say for how long. A minute is this project's guess
            // and is marked as one; the alternative is asking again at once, which is the
            // behaviour being fixed.
            settings.askAgainAfter = Date().addingTimeInterval(wait ?? 60)
        } else {
            settings.askAgainAfter = nil
        }
    }

    var totalErrors: Int { data.series.total }

    var hasOutage: Bool { data.monitors.contains { $0.isActive && !$0.isHealthy } }

    /// Loaded once so Settings can offer the filter only when there is more than one to pick.
    func loadEnvironments() async {
        guard let client else { return }
        data.environments = (try? await client.environments()) ?? []
    }
}
