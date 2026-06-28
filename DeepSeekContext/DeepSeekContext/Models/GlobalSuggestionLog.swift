import Foundation

enum SuggestionStatus: String, CaseIterable {
    case accepted
    case rejected
}

struct GlobalSuggestionLog: Identifiable, Equatable {
    let id: Int64
    let parentId: Int64?
    let content: String
    let reason: String?
    let contentHash: String?
    let status: SuggestionStatus
    let rejectionFeedback: String?
    let createdAt: Date

    init(
        id: Int64,
        parentId: Int64? = nil,
        content: String,
        reason: String? = nil,
        contentHash: String? = nil,
        status: SuggestionStatus,
        rejectionFeedback: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.parentId = parentId
        self.content = content
        self.reason = reason
        self.contentHash = contentHash
        self.status = status
        self.rejectionFeedback = rejectionFeedback
        self.createdAt = createdAt
    }
}
