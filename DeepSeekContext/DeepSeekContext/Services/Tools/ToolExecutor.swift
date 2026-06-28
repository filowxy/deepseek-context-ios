import Foundation

/// Outcome of a single tool execution.
enum ToolResult: Equatable {
    case search(SearchResult)
    case browse(BrowseResult)
    case failed(String)
}

struct ToolTimeoutError: Error {}

/// Executes AI-initiated tool calls with per-type concurrency limits.
/// ponytail: ToolExecutor is an actor, so per-type max concurrency of 1 is implicit.
/// Upgrade path: if concurrency limits change, replace actor isolation with explicit semaphores.
actor ToolExecutor {
    static let shared = ToolExecutor()

    private let searchService: SearchService
    private let browseService: WebBrowseService

    init(searchService: SearchService = .shared, browseService: WebBrowseService = .shared) {
        self.searchService = searchService
        self.browseService = browseService
    }

    /// Execute a tool, serialized within its type.
    func execute(_ action: XMLTagAction) async -> ToolResult {
        switch action {
        case .search(let payload):
            do {
                let depth = SearchDepth(rawValue: payload.depth) ?? .normal
                let result = try await searchService.search(query: payload.query, depth: depth)
                return .search(result)
            } catch {
                return .failed("search error: \(error)")
            }

        case .open(let payload):
            do {
                let result = try await browseService.browse(url: payload.url)
                return .browse(result)
            } catch {
                return .failed("browse error: \(error)")
            }

        default:
            return .failed("unsupported tool action")
        }
    }

    /// Execute a batch of tools with a global 30-second timeout.
    /// Returns results for completed calls and descriptions of calls that did not start before timeout.
    func executeBatch(_ actions: [XMLTagAction]) async -> (results: [ToolResult], skipped: [String]) {
        let descriptions = actions.map { actionDescription($0) }

        do {
            let results = try await withThrowingTaskGroup(of: [ToolResult].self) { group -> [ToolResult] in
                group.addTask {
                    var results: [ToolResult] = []
                    for action in actions {
                        if Task.isCancelled { break }
                        results.append(await self.execute(action))
                    }
                    return results
                }

                group.addTask {
                    try await Task.sleep(nanoseconds: 30 * 1_000_000_000)
                    throw ToolTimeoutError()
                }

                let results = try await group.next()!
                group.cancelAll()
                return results
            }
            return (results, [])
        } catch {
            // ponytail: without cancellation propagation into network calls, we cannot know how many
            // actually finished before timeout; report all remaining as skipped.
            return (results: [], skipped: descriptions)
        }
    }

    private func actionDescription(_ action: XMLTagAction) -> String {
        switch action {
        case .search(let payload):
            return "<search> \(payload.query)"
        case .open(let payload):
            return "<open> \(payload.url)"
        default:
            return "<tool>"
        }
    }
}
