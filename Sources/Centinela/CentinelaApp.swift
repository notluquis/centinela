import CentinelaCore
import SwiftUI

@main
struct CentinelaApp: App {
    @State private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MainPanel(state: state)
        } label: {
            MenuBarLabel(state: state)
                // Startup hangs off the label and not off `init()` because the label exists
                // from the moment the app appears in the bar, while the panel is not built
                // until the first time it is opened. A `.task` on the panel would leave the
                // count empty until someone clicked.
                .task {
                    state.start()
                    await state.checkTokenPower()
                }
        }
        // `.window` and not `.menu`: an `NSMenu` cannot draw the sparkline or two-line rows.
        // The cost is that the panel is a real window, which macOS only creates on first open.
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(state: state)
        }
    }
}
