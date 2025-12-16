import SwiftUI

@main
struct UptimeTrayApp: App {
    @StateObject private var model = UptimeViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
                .onAppear { model.start() }
        } label: {
            Label {
                Text(model.menuBarTitle)
                    .monospacedDigit()
            } icon: {
                Image(systemName: AppIcon.app)
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}


