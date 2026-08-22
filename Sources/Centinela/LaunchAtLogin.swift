import Observation
import ServiceManagement

/// Launch at login, via `SMAppService` (macOS 13+).
///
/// The old way — a helper executable in `Contents/Library/LoginItems` registered with
/// `SMLoginItemSetEnabled` — was deprecated in macOS 13 and forces you to ship a second binary.
/// `SMAppService.mainApp` registers the app itself: no helper, no extra code, and the user can
/// see and disable it in System Settings, General, Login Items.
///
/// The status is NOT a boolean: `.requiresApproval` means registration went through but the user
/// has not approved it yet in System Settings. Treating that as "off" would show the switch down
/// while the system has it up and waiting.
@MainActor
@Observable
final class LaunchAtLogin {
    private(set) var status: SMAppService.Status = .notRegistered
    private(set) var lastError: String?

    init() { refresh() }

    var isEnabled: Bool { status == .enabled }

    var needsApproval: Bool { status == .requiresApproval }

    func refresh() { status = SMAppService.mainApp.status }

    func toggle(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        refresh()
    }

    /// Opens the panel where the user approves or revokes the login item. It is the only way:
    /// an app cannot approve itself.
    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
