import XCTest
@testable import DeepSeekContext

final class SearchServiceTests: XCTestCase {

    private struct MockSession: NetworkSession {
        let data: Data
        let statusCode: Int

        func data(from url: URL) async throws -> (Data, URLResponse) {
            (data, response(for: url))
        }

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            (data, response(for: request.url!))
        }

        private func response(for url: URL) -> URLResponse {
            HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        }
    }

    override func setUp() {
        super.setUp()
        // Ensure Bing path is not taken.
        KeychainManager.shared.save("", for: .bingSearchAPIKey)
    }

    func testDuckDuckGoParsing() async throws {
        let html = #"""
        <div class="result">
            <a class="result__a" href="/l/?kh=-1&amp;uddg=https%3A%2F%2Fexample.com">Example Title</a>
            <a class="result__snippet">This is the snippet text.</a>
        </div>
        <div class="result">
            <a class="result__a" href="/l/?uddg=https%3A%2F%2Fexample.org">Second Title</a>
            <a class="result__snippet">Another snippet.</a>
        </div>
        """#
        let session = MockSession(data: html.data(using: .utf8)!, statusCode: 200)
        let service = SearchService(session: session)
        let result = try await service.search(query: "test", depth: .normal)

        XCTAssertEqual(result.query, "test")
        XCTAssertEqual(result.results.count, 2)
        XCTAssertEqual(result.results[0].title, "Example Title")
        XCTAssertTrue(result.results[0].snippet.contains("This is the snippet"))
    }

    func testBingPathWhenKeyConfigured() async throws {
        KeychainManager.shared.save("fake-key", for: .bingSearchAPIKey)
        defer { KeychainManager.shared.save("", for: .bingSearchAPIKey) }

        let json: [String: Any] = [
            "webPages": [
                "totalEstimatedMatches": 99,
                "value": [
                    ["name": "Bing Title", "url": "https://bing.com", "snippet": "Bing snippet"]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        let session = MockSession(data: data, statusCode: 200)
        let service = SearchService(session: session)
        let result = try await service.search(query: "bing", depth: .quick)

        XCTAssertEqual(result.totalEstimated, 99)
        XCTAssertEqual(result.results.count, 1)
        XCTAssertEqual(result.results.first?.title, "Bing Title")
    }

    func testInvalidResponseThrows() async {
        let session = MockSession(data: Data(), statusCode: 500)
        let service = SearchService(session: session)
        do {
            _ = try await service.search(query: "fail", depth: .quick)
            XCTFail("expected error")
        } catch {
            XCTAssertTrue(error is SearchServiceError)
        }
    }
}
