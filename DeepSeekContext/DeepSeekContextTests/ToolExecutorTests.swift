import XCTest
@testable import DeepSeekContext

final class ToolExecutorTests: XCTestCase {

    private struct MockSession: NetworkSession {
        let searchHTML: String
        let browseHTML: String

        func data(from url: URL) async throws -> (Data, URLResponse) {
            (data(for: url), response(for: url))
        }

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            (data(for: request.url!), response(for: request.url!))
        }

        private func data(for url: URL) -> Data {
            if url.host == "html.duckduckgo.com" {
                return searchHTML.data(using: .utf8)!
            }
            return browseHTML.data(using: .utf8)!
        }

        private func response(for url: URL) -> URLResponse {
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        }
    }

    override func setUp() {
        super.setUp()
        // Ensure DuckDuckGo fallback path is taken.
        KeychainManager.shared.save("", for: .bingSearchAPIKey)
    }

    func testExecuteSearch() async throws {
        let html = #"""
        <div class="result">
            <a class="result__a" href="/l/?uddg=https%3A%2F%2Fexample.com">Result Title</a>
            <a class="result__snippet">Result snippet text.</a>
        </div>
        """#
        let session = MockSession(searchHTML: html, browseHTML: "")
        let executor = ToolExecutor(
            searchService: SearchService(session: session),
            browseService: WebBrowseService(session: session)
        )

        let action = XMLTagAction.search(.init(query: "test", depth: "normal"))
        let result = await executor.execute(action)

        guard case .search(let searchResult) = result else {
            XCTFail("expected search result, got \(result)")
            return
        }
        XCTAssertEqual(searchResult.query, "test")
        XCTAssertEqual(searchResult.results.count, 1)
        XCTAssertEqual(searchResult.results.first?.title, "Result Title")
    }

    func testExecuteOpen() async throws {
        let html = """
        <html><head><title>Page Title</title></head>
        <body>
        <article>
        <p>First paragraph.</p>
        <p>Second paragraph.</p>
        </article>
        </body></html>
        """
        let session = MockSession(searchHTML: "", browseHTML: html)
        let executor = ToolExecutor(
            searchService: SearchService(session: session),
            browseService: WebBrowseService(session: session)
        )

        let action = XMLTagAction.open(.init(url: "https://example.com"))
        let result = await executor.execute(action)

        guard case .browse(let browseResult) = result else {
            XCTFail("expected browse result, got \(result)")
            return
        }
        XCTAssertEqual(browseResult.title, "Page Title")
        XCTAssertTrue(browseResult.content.contains("First paragraph"))
    }

    func testMixedBatchReturnsInOrder() async throws {
        let searchHTML = #"""
        <div class="result">
            <a class="result__a" href="/l/?uddg=https%3A%2F%2Fexample.com">Batch Title</a>
            <a class="result__snippet">Batch snippet.</a>
        </div>
        """#
        let browseHTML = """
        <html><head><title>Batch Page</title></head>
        <body><article><p>Batch content.</p></article></body></html>
        """
        let session = MockSession(searchHTML: searchHTML, browseHTML: browseHTML)
        let executor = ToolExecutor(
            searchService: SearchService(session: session),
            browseService: WebBrowseService(session: session)
        )

        let actions: [XMLTagAction] = [
            .search(.init(query: "first", depth: "quick")),
            .open(.init(url: "https://example.com")),
            .search(.init(query: "second", depth: "quick"))
        ]
        let (results, skipped) = await executor.executeBatch(actions)

        XCTAssertEqual(results.count, 3)
        XCTAssertTrue(skipped.isEmpty)
        XCTAssertTrue(results[0].isSearch)
        XCTAssertTrue(results[1].isBrowse)
        XCTAssertTrue(results[2].isSearch)
    }

    func testUnsupportedActionReturnsFailed() async {
        let executor = ToolExecutor()
        let action = XMLTagAction.mark(.init(type: .userask, lev: 0, content: "x", tags: [], idemKey: "k"))
        let result = await executor.execute(action)

        guard case .failed(let message) = result else {
            XCTFail("expected failed result, got \(result)")
            return
        }
        XCTAssertTrue(message.contains("unsupported"))
    }
}

private extension ToolResult {
    var isSearch: Bool {
        if case .search = self { return true }
        return false
    }

    var isBrowse: Bool {
        if case .browse = self { return true }
        return false
    }
}
