import XCTest

@testable import UptimeTray

final class UptimeCalculatorTests: XCTestCase {
    func testMergesOverlappingIntervals() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let a = DateInterval(start: base, end: base.addingTimeInterval(60))
        let b = DateInterval(start: base.addingTimeInterval(30), end: base.addingTimeInterval(120))
        let c = DateInterval(start: base.addingTimeInterval(200), end: base.addingTimeInterval(240))

        let merged = UptimeCalculator.mergeIntervals([a, b, c])
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged[0].start, a.start)
        XCTAssertEqual(merged[0].end, b.end)
        XCTAssertEqual(merged[1], c)
    }

    func testComputesOverallUptimeAndIncidentAverage() {
        // Window = 1 day
        let now = Date(timeIntervalSince1970: 2_000_000)
        let oneDayAgo = now.addingTimeInterval(-86400)

        // A 60-minute incident inside window.
        let incidentStart = oneDayAgo.addingTimeInterval(3600)
        let incidentDesc = """
        Type: Incident
        Affected Components: API
        Duration: 1 hour
        """

        // Overlapping 30-minute maintenance also inside window (should merge downtime with incident).
        let maintStart = incidentStart.addingTimeInterval(1800)
        let maintDesc = """
        Type: Maintenance
        Affected Components: API, Web
        Duration: 30 minutes
        """

        let items: [RssItem] = [
            RssItem(title: "Incident", pubDate: incidentStart, description: incidentDesc, type: "incident", components: ["API"]),
            RssItem(title: "Maint", pubDate: maintStart, description: maintDesc, type: "maintenance", components: ["API", "Web"]),
        ]

        let summary = UptimeCalculator.computeUptime(items: items, days: 1, now: now)

        // Downtime should be 60 + 30 overlap => 90 minutes total merged? Actually:
        // Incident [t, t+60], maintenance [t+30, t+60] => union is 60 minutes, not 90.
        XCTAssertEqual(summary.mergedIntervals.count, 1)
        XCTAssertEqual(summary.totalDowntime, 60 * 60, accuracy: 0.0001)

        // Window is exactly 86400 seconds; uptime = 1 - 3600/86400 = 0.9583333...
        XCTAssertEqual(summary.uptimePct, (1.0 - (3600.0 / 86400.0)) * 100.0, accuracy: 0.000001)

        // Incident average uses full duration, count = 1, avg = 1 hour
        XCTAssertEqual(summary.incidentCount, 1)
        XCTAssertEqual(summary.avgIncidentResolution, 3600, accuracy: 0.0001)

        // Component stats: API should have same merged downtime; Web should only have 30 minutes (maintenance window).
        XCTAssertEqual(summary.componentStats["API"]?.downtime, 60 * 60, accuracy: 0.0001)
        XCTAssertEqual(summary.componentStats["Web"]?.downtime, 30 * 60, accuracy: 0.0001)
    }
}


