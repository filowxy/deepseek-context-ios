import Foundation

enum WebBrowseError: Error {
    case invalidURL
    case requestFailed(Int)
    case tooLarge
    case extractionFailed
    case timeout
}

struct BrowseResult: Equatable {
    let title: String?
    let content: String
}

/// Fetches and extracts readable text from a web page.
actor WebBrowseService {
    static let shared = WebBrowseService()

    private let session: NetworkSession
    private let timeout: TimeInterval = 15
    private let maxBytes = 2 * 1024 * 1024

    init(session: NetworkSession = URLSession.shared) {
        self.session = session
    }

    func browse(url: String) async throws -> BrowseResult {
        guard let url = URL(string: url) else { throw WebBrowseError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("WorldScapeApp/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = timeout

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw WebBrowseError.requestFailed(0) }
        guard http.statusCode == 200 else { throw WebBrowseError.requestFailed(http.statusCode) }
        guard data.count <= maxBytes else { throw WebBrowseError.tooLarge }

        guard let html = String(data: data, encoding: .utf8) else {
            throw WebBrowseError.extractionFailed
        }

        let title = extractTitle(html)
        if let readable = extractReadable(html) {
            return BrowseResult(title: title, content: readable)
        }

        // Fallback: plain text prefix.
        let plain = stripHTML(html)
            .components(separatedBy: .whitespacesAndNewlines)
            .joined(separator: " ")
        let prefix = String(plain.prefix(4000))
        return BrowseResult(title: title, content: prefix)
    }

    // MARK: - Extraction helpers

    private func extractTitle(_ html: String) -> String? {
        let pattern = #"<title[^>]*>(.*?)</title>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// ponytail: lightweight readability heuristic; replace with a real algorithm if needed.
    private func extractReadable(_ html: String) -> String? {
        // Prefer <article>, then <main>, then the largest <div> by paragraph count.
        for tag in ["article", "main"] {
            if let body = firstTagContent(tag: tag, in: html) {
                let text = collapseWhitespace(stripHTML(body))
                if text.count > 200 { return text }
            }
        }

        // Largest <div> heuristic.
        let divs = tagContents(tag: "div", in: html)
        let best = divs.max { countParagraphs($0) < countParagraphs($1) }
        if let best = best, countParagraphs(best) >= 3 {
            return collapseWhitespace(stripHTML(best))
        }
        return nil
    }

    private func firstTagContent(tag: String, in html: String) -> String? {
        tagContents(tag: tag, in: html).first
    }

    private func tagContents(tag: String, in html: String) -> [String] {
        let pattern = #"<"# + NSRegularExpression.escapedPattern(for: tag) + #"[^>]*>(.*?)<\/"# + NSRegularExpression.escapedPattern(for: tag) + #">"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            return []
        }
        return regex.matches(in: html, options: [], range: NSRange(html.startIndex..., in: html)).compactMap { match in
            guard let range = Range(match.range(at: 1), in: html) else { return nil }
            return String(html[range])
        }
    }

    private func countParagraphs(_ html: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: #"<p[\s>]"#, options: [.caseInsensitive]) else { return 0 }
        return regex.matches(in: html, options: [], range: NSRange(html.startIndex..., in: html)).count
    }

    private func stripHTML(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) else { return text }
        return regex.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: "")
    }

    private func collapseWhitespace(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
