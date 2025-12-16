import Foundation

struct UptimeCalculator {
    static let defaultWindowDays = 30

    static func computeUptime(items: [RssItem], days: Int = defaultWindowDays, now: Date = Date()) -> UptimeSummary {
        let windowEnd = now
        let windowStart = Calendar(identifier: .gregorian).date(byAdding: .day, value: -days, to: windowEnd) ?? windowEnd.addingTimeInterval(TimeInterval(-days * 86400))

        var intervals: [DateInterval] = []
        var incidentTotal: TimeInterval = 0
        var incidentCount = 0
        var componentIntervals: [String: [DateInterval]] = [:]

        for item in items {
            guard let dur = parseDuration(from: item.description) else {
                continue
            }

            let start = item.pubDate
            let end = start.addingTimeInterval(dur)

            // Match uptime.py:
            // - Incident average uses the full duration (not clipped)
            // - Incident must start inside the window
            if item.type.lowercased() == "incident", start >= windowStart, start <= windowEnd {
                incidentTotal += dur
                incidentCount += 1
            }

            // Clip to analysis window
            if end <= windowStart || start >= windowEnd {
                continue
            }

            let clippedStart = max(start, windowStart)
            let clippedEnd = min(end, windowEnd)
            if clippedStart < clippedEnd {
                let interval = DateInterval(start: clippedStart, end: clippedEnd)
                intervals.append(interval)

                for comp in item.components {
                    componentIntervals[comp, default: []].append(interval)
                }
            }
        }

        let merged = mergeIntervals(intervals)
        let totalDowntime = merged.reduce(0) { $0 + $1.duration }

        let windowSeconds = windowEnd.timeIntervalSince(windowStart)
        let uptimePct: Double
        if windowSeconds <= 0 {
            uptimePct = 100.0
        } else {
            let raw = (1.0 - (totalDowntime / windowSeconds)) * 100.0
            uptimePct = min(100.0, max(0.0, raw))
        }

        let avgIncidentResolution: TimeInterval? = incidentCount > 0 ? (incidentTotal / Double(incidentCount)) : nil

        var componentStats: [String: ComponentUptimeStats] = [:]
        for (comp, compIntervals) in componentIntervals {
            let mergedComp = mergeIntervals(compIntervals)
            let compDowntime = mergedComp.reduce(0) { $0 + $1.duration }

            let compUptimePct: Double
            if windowSeconds <= 0 {
                compUptimePct = 100.0
            } else {
                let raw = (1.0 - (compDowntime / windowSeconds)) * 100.0
                compUptimePct = min(100.0, max(0.0, raw))
            }

            componentStats[comp] = ComponentUptimeStats(
                uptimePct: compUptimePct,
                downtime: compDowntime,
                intervals: mergedComp
            )
        }

        return UptimeSummary(
            windowDays: days,
            windowStart: windowStart,
            windowEnd: windowEnd,
            uptimePct: uptimePct,
            totalDowntime: totalDowntime,
            mergedIntervals: merged,
            incidentCount: incidentCount,
            avgIncidentResolution: avgIncidentResolution,
            componentStats: componentStats
        )
    }

    static func mergeIntervals(_ intervals: [DateInterval]) -> [DateInterval] {
        guard !intervals.isEmpty else { return [] }

        let sorted = intervals.sorted { $0.start < $1.start }
        var merged: [DateInterval] = [sorted[0]]

        for interval in sorted.dropFirst() {
            let last = merged[merged.count - 1]
            if interval.start <= last.end { // overlap / touch
                let newEnd = max(last.end, interval.end)
                merged[merged.count - 1] = DateInterval(start: last.start, end: newEnd)
            } else {
                merged.append(interval)
            }
        }

        return merged
    }

    // MARK: - Parsing helpers (mirrors uptime.py)

    static func parseDuration(from description: String) -> TimeInterval? {
        guard !description.isEmpty else { return nil }
        guard let durText = captureFirstGroup(pattern: #"Duration:\s*([^\n\r]+)"#, in: description, options: [.caseInsensitive]) else {
            return nil
        }

        let hours = Int(captureFirstGroup(pattern: #"(\d+)\s*hour"#, in: durText, options: [.caseInsensitive]) ?? "") ?? 0
        let minutes = Int(captureFirstGroup(pattern: #"(\d+)\s*minute"#, in: durText, options: [.caseInsensitive]) ?? "") ?? 0

        if hours == 0 && minutes == 0 { return nil }
        return TimeInterval(hours * 3600 + minutes * 60)
    }

    static func extractType(from description: String) -> String? {
        guard !description.isEmpty else { return nil }
        guard let raw = captureFirstGroup(pattern: #"Type:\s*([A-Za-z]+)"#, in: description, options: [.caseInsensitive]) else {
            return nil
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func extractComponents(from description: String) -> [String] {
        guard !description.isEmpty else { return [] }
        guard let raw = captureFirstGroup(pattern: #"Affected Components:\s*([^\n\r]+)"#, in: description, options: [.caseInsensitive]) else {
            return []
        }
        return raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func captureFirstGroup(pattern: String, in text: String, options: NSRegularExpression.Options = []) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = re.firstMatch(in: text, options: [], range: range), match.numberOfRanges >= 2 else { return nil }
        guard let r = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}


