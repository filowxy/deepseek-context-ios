import Foundation

actor ReminderEngine {
    static let shared = ReminderEngine()
    private init() {}

    private var markDAO: ContextMarkDAO { ContextMarkDAO.shared }

    static let firstReminderCounter: Int64 = 5
    static let reminderCycles: [Int64] = [10, 20, 30, 50]

    /// Determine whether a mark should be reminded at the current counter.
    func shouldRemind(mark: ContextMark, currentCount: Int64) -> Bool {
        guard currentCount >= Self.firstReminderCounter else { return false }
        guard let last = mark.lastRemindCounter else {
            return true
        }
        let cycle = Self.reminderCycles[safe: mark.lev] ?? Self.reminderCycles[0]
        return currentCount - last >= cycle
    }

    /// Find all marks that need reminding and update their last_remind_counter.
    func pendingReminders(for conversationId: String, currentCount: Int64) async throws -> [ContextMark] {
        let marks = try await markDAO.fetch(byConversationId: conversationId)
        var pending: [ContextMark] = []
        for mark in marks {
            if shouldRemind(mark: mark, currentCount: currentCount) {
                pending.append(mark)
            }
        }
        return pending
    }

    /// Record that a reminder was delivered for the given mark.
    func markReminded(id: Int64, at counter: Int64) async throws {
        try await markDAO.updateLastRemindCounter(id: id, counter: counter)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
