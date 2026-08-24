import Observation
import Sparkle

/// Automatic updates through Sparkle.
///
/// **Apple's signing is not what an update is checked against, contrary to what this project
/// claimed at first.** Sparkle's own update policy says so in `SUUpdateValidator.m`: it refuses
/// to *remove* code signing or EdDSA keys, and spells out that "if no Apple Code Signing
/// certificate is available, adhoc signing can be used at minimum". Sparkle's own framework
/// ships ad-hoc signed (`codesign -dv` reports `Signature=adhoc`, `TeamIdentifier=not set`);
/// these builds carry a self-signed certificate, which is not a Developer ID either. Neither
/// stands in the way.
///
/// What the update is verified against is the **EdDSA signature** of the archive, made with a key
/// pair of ours: the public half sits in `Info.plist` as `SUPublicEDKey` and the private half
/// never leaves the release runner. That check does not involve Apple at all.
///
/// The sandbox is what costs something: installing means writing outside the container, so
/// Sparkle does it from `Installer.xpc`, which needs `SUEnableInstallerLauncherService` and two
/// `mach-lookup` exceptions in the entitlements. Those are the only two lines in
/// `Centinela.entitlements` that are not "reach the network".
@MainActor
@Observable
final class Updater {
    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var watch: [NSKeyValueObservation] = []

    /// Mirrored out of Sparkle rather than read through it.
    ///
    /// `canCheckForUpdates` is documented KVO-compliant in Sparkle's own header. `lastUpdateCheckDate`
    /// is **not**: its notification comes from `-updateLastUpdateCheckDate` calling
    /// `will/didChangeValueForKey` by hand (`SPUUpdater.m`, read against Sparkle 2.9.6). If a
    /// version bump drops that, this line goes stale again silently and no test here can see it,
    /// because the app target has none.
    ///
    /// `SPUUpdater` is an Objective-C object and knows nothing about Observation, so a computed
    /// property reading it is invisible to SwiftUI: the About tab showed whatever those values
    /// were when it was first drawn and never moved again. Press "Check for updates", watch the
    /// check finish, and "Last checked" still said what it said before. Both are KVO-compliant,
    /// so they are mirrored into stored properties that SwiftUI can see.
    private(set) var canCheck = false
    private(set) var lastCheck: Date?

    init() {
        // `startingUpdater: true` so the scheduled check runs on its own. The user-facing
        // switch is `SUEnableAutomaticChecks` in `Info.plist`, which Sparkle also exposes in its
        // own UI, so there is no second setting of ours to keep in sync.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        let updater = controller.updater
        // Seeded here, and `.new` only: with `.initial` the observer fires synchronously during
        // `observe(...)` and schedules a task that assigns exactly what these two lines already
        // assigned. Two mechanisms doing one job is one of them going quietly wrong later.
        canCheck = updater.canCheckForUpdates
        lastCheck = updater.lastUpdateCheckDate
        // The handler reads through `self`, not through the `SPUUpdater` the callback hands over.
        // That object is not `Sendable`, and capturing it into a `@MainActor` task sends it across
        // an isolation boundary — quiet under Swift 5 language mode, diagnosed the moment this
        // moves to 6. `self` is already on the main actor and holds the controller.
        watch = [
            updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.canCheck = self.controller.updater.canCheckForUpdates
                }
            },
            updater.observe(\.lastUpdateCheckDate, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.lastCheck = self.controller.updater.lastUpdateCheckDate
                }
            }
        ]
    }

    func checkNow() {
        controller.updater.checkForUpdates()
    }
}
