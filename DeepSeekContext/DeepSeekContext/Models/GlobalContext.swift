import Foundation

struct GlobalContext: Identifiable, Equatable {
    let id: Int64
    let content: String
    let createdAt: Date
    var deleted: Bool

    init(id: Int64, content: String, createdAt: Date = Date(), deleted: Bool = false) {
        self.id = id
        self.content = content
        self.createdAt = createdAt
        self.deleted = deleted
    }
}
