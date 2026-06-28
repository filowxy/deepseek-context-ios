import Foundation

enum SearchServiceError: Error {
    case invalidURL
    case invalidResponse
    case decodingFailed
    case timeout
}

/// Network abstraction for testability.
protocol NetworkSession {
    func data(from url: URL) async throws -> (Data, URLResponse)
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: NetworkSession {}

/// Performs web searches using Bing when configured, falling back to DuckDuckGo HTML scraping.
actor SearchService {
    static let shared = SearchService()

    private let keychain = KeychainManager.shared
    private let session: NetworkSession
    private let timeout: TimeInterval = 10

    init(session: NetworkSession = URLSession.shared) {
        self.session = session
    }

    /// Execute a search with the configured engine and requested depth.
    func search(query: String, depth: SearchDepth = .normal) async throws -> SearchResult {
        let count = depth.resultCount
        if let bingKey = keychain.read(.bingSearchAPIKey), !bingKey.isEmpty {
            return try await searchBing(query: query, count: count, key: bingKey)
        }
        return try await searchDuckDuckGo(query: query, count: count)
    }

    // MARK: - Bing

    private func searchBing(query: String, count: Int, key: String) async throws -> SearchResult {
        var components = URLComponents(string: "https://api.bing.microsoft.com/v7.0/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "count", value: String(count))
        ]
        guard let url = components.url else { throw SearchServiceError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.timeoutInterval = timeout

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SearchServiceError.invalidResponse
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let webPages = json["webPages"] as? [String: Any],
              let totalEstimate = webPages["totalEstimatedMatches"] as? Int,
              let values = webPages["value"] as? [[String: Any]] else {
            throw SearchServiceError.decodingFailed
        }

        let items: [SearchResult.Item] = values.prefix(count).compactMap { value in
            guard let title = value["name"] as? String,
                  let urlString = value["url"] as? String,
                  let snippet = value["snippet"] as? String else { return nil }
            return SearchResult.Item(title: title, url: urlString, snippet: snippet)
        }
        return SearchResult(query: query, totalEstimated: totalEstimate, results: items)
    }

    // MARK: - DuckDuckGo HTML fallback

    private func searchDuckDuckGo(query: String, count: Int) async throws -> SearchResult {
        var components = URLComponents(string: "https://html.duckduckgo.com/html/")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        guard let url = components.url else { throw SearchServiceError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("WorldScapeApp/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = timeout

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else {
            throw SearchServiceError.invalidResponse
        }

        let items = parseDuckDuckGoHTML(html).prefix(count)
        return SearchResult(query: query, totalEstimated: items.count, results: Array(items))
    }

    /// ponytail: naive regex extraction from DuckDuckGo HTML; upgrade to a proper parser if DOM shifts.
    private func parseDuckDuckGoHTML(_ html: String) -> [SearchResult.Item] {
        let resultBlocks = html.components(separatedBy: "<div class=\"result\"")
        return resultBlocks.compactMap { block in
            guard let titleMatch = firstMatch(pattern: #"<a[^>]+class=\"result__a\"[^>]*>(.*?)</a>"#, in: block),
                  let snippetMatch = firstMatch(pattern: #"<a[^>]+class=\"result__snippet\"[^>]*>(.*?)</a>"#, in: block) else {
                return nil
            }
            let title = stripHTML(titleMatch)
            let snippet = stripHTML(snippetMatch)
            let url = firstMatch(pattern: #"href=\"([^\"]+)\""#, in: block)?.removingPercentEncoding ?? ""
            guard !title.isEmpty else { return nil }
            return SearchResult.Item(title: title, url: url, snippet: snippet)
        }
    }

    private func firstMatch(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    private func stripHTML(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) else { return text }
        let clean = regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "")
        return clean.decodingHTMLEntities().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    /// ponytail: minimal HTML entity decoding; expand if more entities appear.
    func decodingHTMLEntities() -> String {
        self.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}
