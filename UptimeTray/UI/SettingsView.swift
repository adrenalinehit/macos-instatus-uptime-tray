import SwiftUI

struct SettingsView: View {
    @AppStorage("windowDays") private var windowDays: Int = UptimeCalculator.defaultWindowDays
    @AppStorage("targetUptimePct") private var targetUptimePctString: String = ""

    var body: some View {
        Form {
            Section("Window") {
                Stepper(value: $windowDays, in: 1...365) {
                    Text("Look back \(windowDays) day(s)")
                }
            }

            Section("Target uptime (optional)") {
                TextField("e.g. 99.95000", text: $targetUptimePctString)
                    .textFieldStyle(.roundedBorder)

                Text("If set, any overall/component uptime below this value is shown in red.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 420)
    }
}


