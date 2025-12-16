import Foundation

struct RssClient {
    static let defaultFeedURLString = "https://status.bigchange.com/history.rss"

    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchFeed(urlString: String = defaultFeedURLString) async throws -> Data {
        guard let url = URL(string: urlString) else { throw UptimeError.invalidURL }

        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 15

        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw UptimeError.httpError(statusCode: http.statusCode)
        }
        return data
    }
}


