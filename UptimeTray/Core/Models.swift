import Foundation

struct RssItem: Equatable {
    let title: String
    let pubDate: Date
    let description: String
    let type: String
    let components: [String]
}

struct ComponentUptimeStats: Equatable {
    let uptimePct: Double
    let downtime: TimeInterval
    let intervals: [DateInterval]
}

struct UptimeSummary: Equatable {
    let windowDays: Int
    let windowStart: Date
    let windowEnd: Date
    let uptimePct: Double
    let totalDowntime: TimeInterval
    let mergedIntervals: [DateInterval]
    let incidentCount: Int
    let avgIncidentResolution: TimeInterval?
    let componentStats: [String: ComponentUptimeStats]
}

enum UptimeError: Error, LocalizedError, Equatable {
    case invalidURL
    case httpError(statusCode: Int)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid feed URL."
        case .httpError(let statusCode):
            return "Feed request failed (HTTP \(statusCode))."
        case .parseError(let msg):
            return "Feed parse failed: \(msg)"
        }
    }
}


