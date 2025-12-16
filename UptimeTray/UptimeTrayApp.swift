import SwiftUI

@main
struct UptimeTrayApp: App {
    @StateObject private var model = UptimeViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
                .onAppear { model.start() }
        } label: {
            Text(model.menuBarTitle)
                .monospacedDigit()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}


