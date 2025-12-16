import Foundation

struct RssParser {
    func parse(feedData: Data) throws -> [RssItem] {
        let delegate = Delegate()
        let parser = XMLParser(data: feedData)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false

        guard parser.parse() else {
            let msg = parser.parserError?.localizedDescription ?? "Unknown XML error"
            throw UptimeError.parseError(msg)
        }

        return delegate.items
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        private(set) var items: [RssItem] = []

        private var inItem = false
        private var currentElement: String?

        private var title = ""
        private var pubDate = ""
        private var desc = ""

        private var buffer = ""

        private lazy var pubDateFormatter: DateFormatter = {
            // RFC 822-ish, e.g. "Tue, 16 Dec 2025 12:34:56 GMT"
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = TimeZone(secondsFromGMT: 0)
            df.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            return df
        }()

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            if elementName == "item" {
                inItem = true
                title = ""
                pubDate = ""
                desc = ""
            }
            guard inItem else { return }
            currentElement = elementName
            buffer = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard inItem, currentElement != nil else { return }
            buffer += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            guard inItem else { return }

            if elementName == "title" {
                title += buffer
            } else if elementName == "pubDate" {
                pubDate += buffer
            } else if elementName == "description" {
                desc += buffer
            } else if elementName == "item" {
                inItem = false

                let pubDateTrim = pubDate.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let date = pubDateFormatter.date(from: pubDateTrim) else {
                    // Skip unparseable items (mirrors Python's "continue")
                    return
                }

                let descText = desc
                let incidentType = UptimeCalculator.extractType(from: descText) ?? ""
                let components = UptimeCalculator.extractComponents(from: descText)

                items.append(
                    RssItem(
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        pubDate: date,
                        description: descText,
                        type: incidentType,
                        components: components
                    )
                )
            }

            currentElement = nil
            buffer = ""
        }
    }
}


