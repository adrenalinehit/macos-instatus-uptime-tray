import SwiftUI

struct SettingsView: View {
    @AppStorage("windowDays") private var windowDays: Int = UptimeCalculator.defaultWindowDays
    @AppStorage("targetUptimePct") private var targetUptimePctString: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Form {
                windowSection
                targetSection
                actionsSection
            }
            .formStyle(.grouped)
        }
        .padding(20)
        .frame(minWidth: 460)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Settings")
                .font(.title2.weight(.semibold))
            Text("Tune the rolling window and optional alert threshold used by the menu bar summary.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityAddTraits(.isHeader)
    }

    private var windowSection: some View {
        Section("Window") {
            LabeledContent("Look back") {
                Stepper(value: $windowDays, in: 1...365) {
                    Text("\(windowDays) day\(windowDays == 1 ? "" : "s")")
                        .monospacedDigit()
                }
                .labelsHidden()
            }

            Text("Uptime is computed over the last \(windowDays) day\(windowDays == 1 ? "" : "s").")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var targetSection: some View {
        Section("Target uptime (optional)") {
            LabeledContent("Threshold") {
                HStack(spacing: 8) {
                    TextField("99.95000", text: $targetUptimePctString)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                        .onChange(of: targetUptimePctString) { _, newValue in
                            targetUptimePctString = sanitizePercentInput(newValue)
                        }
                    Text("%")
                        .foregroundStyle(.secondary)
                }
            }

            Text("If set, any overall/component uptime below this value is shown in red. Leave blank to disable.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var actionsSection: some View {
        Section {
            Button("Reset to defaults") {
                windowDays = UptimeCalculator.defaultWindowDays
                targetUptimePctString = ""
            }
        }
    }

    private func sanitizePercentInput(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Keep only digits and a single dot, and cap length to avoid absurd values.
        var result = ""
        var dotSeen = false
        for ch in trimmed {
            if ch.isNumber {
                result.append(ch)
            } else if ch == ".", !dotSeen {
                dotSeen = true
                result.append(ch)
            }
            if result.count >= 10 { break }
        }
        return result
    }
}


