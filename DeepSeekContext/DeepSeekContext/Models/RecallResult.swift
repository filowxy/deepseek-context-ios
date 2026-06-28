import Foundation

struct RecallResult: Equatable {
    struct Item: Equatable {
        let markId: Int64
        let lev: Int
        let content: String
        let tags: [String]
        let createdAt: Date
    }

    let items: [Item]
    let total: Int
    let truncated: Bool
    let searchId: String
    let message: String
}
