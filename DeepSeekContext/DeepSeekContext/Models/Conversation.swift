import Foundation

struct Conversation: Identifiable, Equatable {
    let id: String
    var title: String?
    let createdAt: Date
    var updatedAt: Date
    var isActive: Bool

    init(id: String, title: String? = nil, createdAt: Date = Date(), updatedAt: Date = Date(), isActive: Bool = true) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isActive = isActive
    }
}
