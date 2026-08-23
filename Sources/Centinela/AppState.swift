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

    var series: EventSeries = .init(points: [])
    var monitors: [UptimeMonitor] = []
    var issues: [SentryIssue] = []
    var forReview: [SentryIssue] = []
    var releases: [Release] = []

    var loading = false
    var lastError: String?
    var tokenTooPowerful = false
    var deprecation: DeprecationNotice?

    /// Persisted: after a restart the panel used to show nothing instead of saying how old the
    /// data on screen is. Not a secret, so `UserDefaults` rather than the Keychain.
    var lastUpdated: Date? {
        didSet {
            UserDefaults.standard.set(lastUpdated?.timeIntervalSince1970 ?? 0, forKey: "ultimaActualizacion")
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
        let saved = UserDefaults.standard.double(forKey: "ultimaActualizacion")
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
        return SentryClient(credentials: credentials) { [weak self] notice in
            Task { @MainActor in self?.deprecation = notice }
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
            lastError = refreshFailure
        }
        guard let client else { return }
        loading = true
        defer { loading = false }
        do {
            async let series = client.errorSeries(window: settings.window)
            async let monitors = client.uptimeMonitors()
            self.series = try await series
            self.monitors = try await monitors
            lastError = nil
            lastUpdated = .now
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func refreshExpensive() async {
        guard let client else { return }
        loading = true
        defer { loading = false }
        do {
            async let issues = client.unresolvedIssues(window: settings.window, limit: settings.maxIssues)
            async let forReview = client.issuesForReview()
            async let releases = client.latestReleases()
            self.issues = try await issues
            self.forReview = try await forReview
            self.releases = try await releases
            lastError = nil
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func checkTokenPower() async {
        guard let client else { return }
        tokenTooPowerful = await !client.tokenLooksReadOnly()
    }

    // MARK: - What gets drawn up top

    var totalErrors: Int { series.total }

    var hasOutage: Bool { monitors.contains { $0.isActive && !$0.isHealthy } }
}
