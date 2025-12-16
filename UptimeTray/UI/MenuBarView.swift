import AppKit
import SwiftUI

private func roundPct3(_ pct: Double) -> Double {
    (pct * 1000).rounded() / 1000
}

private struct IconRow: View {
    let systemName: String
    let text: String
    var emphasized: Bool = false
    var iconColor: Color? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemName)
                .foregroundStyle(iconColor ?? .secondary)
                .frame(width: 16)
            Text(text)
                .font(emphasized ? .subheadline.weight(.semibold) : .subheadline)
        }
    }
}

final class UptimeViewModel: ObservableObject {
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var summary: UptimeSummary?

    @AppStorage("windowDays") private var windowDays: Int = UptimeCalculator.defaultWindowDays
    @AppStorage("targetUptimePct") private var targetUptimePctString: String = ""

    private let client = RssClient()
    private let parser = RssParser()
    private var timer: Timer?
    private var hasStarted: Bool = false

    var targetUptimePct: Double? {
        let trimmed = targetUptimePctString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let parsed = Double(trimmed) else { return nil }
        return roundPct3(parsed)
    }

    var menuBarTitle: String {
        if isLoading, summary == nil { return "--" }
        guard let pct = summary?.uptimePct else { return "--" }
        return String(format: "%.3f%%", roundPct3(pct))
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        // Immediate refresh + periodic refresh
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        Task { @MainActor in
            isLoading = true
            lastError = nil
        }

        Task {
            do {
                let data = try await client.fetchFeed()
                let items = try parser.parse(feedData: data)
                let computed = UptimeCalculator.computeUptime(items: items, days: windowDays, now: Date())
                await MainActor.run {
                    self.summary = computed
                    self.lastUpdated = Date()
                    self.isLoading = false
                    self.lastError = nil
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }

    func openStatusPage() {
        guard let url = URL(string: "https://status.bigchange.com") else { return }
        NSWorkspace.shared.open(url)
    }
}

struct MenuBarView: View {
    @ObservedObject var model: UptimeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Divider()
            summaryBlock
            if let err = model.lastError {
                Divider()
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Divider()
            actions
        }
        .padding(12)
        .frame(minWidth: 420)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Label("BigChange uptime", systemImage: AppIcon.app)
                .font(.headline)
            Spacer()
            if model.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var summaryBlock: some View {
        if let s = model.summary {
            let target = model.targetUptimePct
            let overallPct = roundPct3(s.uptimePct)
            let overallIsBad = (target != nil && overallPct < target!)

            VStack(alignment: .leading, spacing: 6) {
                IconRow(systemName: AppIcon.window, text: "Window length: \(s.windowDays) days")
                    .foregroundStyle(.secondary)

                IconRow(
                    systemName: AppIcon.downtime,
                    text: "Total recorded downtime: \(formatDuration(s.totalDowntime)) (\(String(format: "%.2f", s.totalDowntime / 60)) minutes)"
                )

                if let t = target {
                    IconRow(
                        systemName: AppIcon.target,
                        text: String(format: "Required uptime target: %.3f%%", t)
                    )
                    .foregroundStyle(.secondary)
                }

                IconRow(
                    systemName: AppIcon.uptime,
                    text: String(format: "Overall uptime: %.3f%%", overallPct),
                    emphasized: true,
                    iconColor: overallIsBad ? .red : nil
                )
                .foregroundStyle(overallIsBad ? .red : .primary)

                Text("Number of downtime intervals used: \(s.mergedIntervals.count)")
                    .font(.subheadline)

                if let avg = s.avgIncidentResolution {
                    Text("Average incident resolution time: \(formatDuration(avg)) (\(String(format: "%.2f", avg / 60)) minutes) across \(s.incidentCount) incident(s)")
                        .font(.subheadline)
                } else {
                    Text("Average incident resolution time: no incident entries with a duration found in the window")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if !s.componentStats.isEmpty {
                    Divider().padding(.vertical, 4)
                    Text("Average uptime per component over window:")
                        .font(.subheadline.weight(.semibold))

                    ForEach(s.componentStats.keys.sorted(), id: \.self) { comp in
                        if let stats = s.componentStats[comp] {
                            let compPct = roundPct3(stats.uptimePct)
                            let isBad = (target != nil && compPct < target!)
                            Text("  \(comp): uptime \(String(format: "%.3f", compPct))% (downtime \(formatDuration(stats.downtime)) / \(String(format: "%.2f", stats.downtime / 60)) minutes)")
                                .font(.caption)
                                .foregroundStyle(isBad ? .red : .primary)
                        }
                    }
                } else {
                    Divider().padding(.vertical, 4)
                    Text("Average uptime per component: no component-level downtime entries with a duration found in the window")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let updated = model.lastUpdated {
                    Divider().padding(.vertical, 4)
                    HStack(spacing: 6) {
                        Image(systemName: AppIcon.lastUpdated)
                            .foregroundStyle(.secondary)
                        Text("Last updated: \(updated.formatted(date: .abbreviated, time: .standard))")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        } else {
            Text("No data yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        HStack {
            Button {
                model.refresh()
            } label: {
                Label("Refresh", systemImage: AppIcon.refresh)
            }
            Button {
                model.openStatusPage()
            } label: {
                Label("Open status page", systemImage: AppIcon.statusPage)
            }
            SettingsLink {
                Label("Settings…", systemImage: AppIcon.settings)
            }
            Spacer()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: AppIcon.quit)
            }
        }
        .buttonStyle(.borderless)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}


