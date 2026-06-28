import Foundation

/// Result of a web search tool call.
struct SearchResult: Equatable {
    struct Item: Equatable {
        let title: String
        let url: String
        let snippet: String
    }

    let query: String
    let totalEstimated: Int
    let results: [Item]
}

/// Depth level controlling how many search results to return.
enum SearchDepth: String {
    case quick    // 3 results
    case normal   // 7 results
    case detailed // 10 results

    var resultCount: Int {
        switch self {
        case .quick: return 3
        case .normal: return 7
        case .detailed: return 10
        }
    }
}
