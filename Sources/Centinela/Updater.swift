import Observation
import Sparkle

/// Automatic updates through Sparkle.
///
/// **Ad-hoc signing is not a blocker, contrary to what this project claimed at first.** Sparkle's
/// own update policy says so in `SUUpdateValidator.m`: it refuses to *remove* code signing or
/// EdDSA keys, and spells out that "if no Apple Code Signing certificate is available, adhoc
/// signing can be used at minimum". Sparkle's own framework ships ad-hoc signed too
/// (`codesign -dv` reports `Signature=adhoc`, `TeamIdentifier=not set`).
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

    init() {
        // `startingUpdater: true` so the scheduled check runs on its own. The user-facing
        // switch is `SUEnableAutomaticChecks` in `Info.plist`, which Sparkle also exposes in its
        // own UI, so there is no second setting of ours to keep in sync.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var canCheck: Bool { controller.updater.canCheckForUpdates }

    /// Last time Sparkle looked, so the About tab can say something truthful instead of nothing.
    var lastCheck: Date? { controller.updater.lastUpdateCheckDate }

    func checkNow() {
        controller.updater.checkForUpdates()
    }
}
