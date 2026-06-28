import XCTest
@testable import DeepSeekContext

final class WebBrowseServiceTests: XCTestCase {

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

    func testExtractsArticleContent() async throws {
        let html = """
        <html><head><title>Page Title</title></head>
        <body>
        <article>
        <p>First paragraph of the article.</p>
        <p>Second paragraph with more detail.</p>
        </article>
        </body></html>
        """
        let session = MockSession(data: html.data(using: .utf8)!, statusCode: 200)
        let service = WebBrowseService(session: session)
        let result = try await service.browse(url: "https://example.com")

        XCTAssertEqual(result.title, "Page Title")
        XCTAssertTrue(result.content.contains("First paragraph"))
        XCTAssertTrue(result.content.contains("Second paragraph"))
    }

    func testFallbackPlainTextPrefix() async throws {
        let html = """
        <html><body>
        <div>Short text.</div>
        </body></html>
        """
        let session = MockSession(data: html.data(using: .utf8)!, statusCode: 200)
        let service = WebBrowseService(session: session)
        let result = try await service.browse(url: "https://example.com")

        XCTAssertNil(result.title)
        XCTAssertTrue(result.content.contains("Short text"))
    }

    func testRequestFailedThrows() async {
        let session = MockSession(data: Data(), statusCode: 404)
        let service = WebBrowseService(session: session)
        do {
            _ = try await service.browse(url: "https://example.com")
            XCTFail("expected error")
        } catch {
            XCTAssertTrue(error is WebBrowseError)
        }
    }
}
