import Foundation

enum RecallScope: String {
    case current
    case parent
    case all
}

actor RecallEngine {
    static let shared = RecallEngine()
    private init() {}

    private var searchDAO: SearchDAO { SearchDAO.shared }
    private var tagDAO: TagDAO { TagDAO.shared }

    /// In-memory cache of full result sets keyed by search_id. Lost on app restart.
    private var searchCache: [String: RecallResult] = [:]

    static let defaultLimit = 7
    static let maxLimit = 20

    /// Recall relevant marks across the requested scope.
    func recall(
        query: String,
        scope: RecallScope,
        conversationId: String,
        parentId: String? = nil,
        limit: Int = Self.defaultLimit
    ) async throws -> RecallResult {
        let effectiveLimit = max(1, min(limit, Self.maxLimit))
        let scopeIds = try await scopeConversationIds(scope: scope, conversationId: conversationId, parentId: parentId)

        var ftsItems = try await searchDAO.searchFullText(query: query, limit: effectiveLimit, scopeConversationIds: scopeIds)
        var seenIds = Set<Int64>(ftsItems.map(\.markId))

        // Phase 2: exact tag match for the query term, appending results not already in phase 1.
        let tagItems = try await tagMatchingItems(tag: query, scopeIds: scopeIds, excluding: &seenIds, limit: effectiveLimit)
        var allItems = ftsItems + tagItems

        let total = allItems.count
        let truncated = total > effectiveLimit
        if truncated {
            allItems = Array(allItems.prefix(effectiveLimit))
        }

        // Populate tags for the returned items.
        var enriched: [RecallResult.Item] = []
        for var item in allItems {
            let tags = try await tagDAO.fetchTags(for: item.markId)
            // ponytail: RecallResult.Item is a struct with let tags, rebuild instead of mutating
            item = RecallResult.Item(markId: item.markId, lev: item.lev, content: item.content, tags: tags, createdAt: item.createdAt)
            enriched.append(item)
        }

        let searchId = generateSearchId(conversationId: conversationId)
        let result = RecallResult(
            items: enriched,
            total: total,
            truncated: truncated,
            searchId: searchId,
            message: truncated ? "找到 \(total) 条相关标记，以下是匹配度最高的 \(effectiveLimit) 条..." : ""
        )
        searchCache[searchId] = result
        return result
    }

    /// Retrieve the full result set previously stored under a search_id.
    func result(bySearchId searchId: String) -> RecallResult? {
        searchCache[searchId]
    }

    private func scopeConversationIds(scope: RecallScope, conversationId: String, parentId: String?) async throws -> [String]? {
        switch scope {
        case .current:
            return [conversationId]
        case .parent:
            if let parentId {
                return [parentId]
            }
            return []
        case .all:
            return nil
        }
    }

    private func tagMatchingItems(
        tag: String,
        scopeIds: [String]?,
        excluding seenIds: inout Set<Int64>,
        limit: Int
    ) async throws -> [RecallResult.Item] {
        let markIds = try await tagDAO.fetchMarkIds(byTag: tag)
        var items: [RecallResult.Item] = []
        for markId in markIds {
            guard !seenIds.contains(markId) else { continue }
            // ponytail: O(n) tag scan is acceptable for small tag libraries; upgrade to JOIN if needed
            if items.count >= limit { break }
            guard let mark = try await ContextMarkDAO.shared.fetch(byId: markId) else { continue }
            if mark.deleted { continue }
            if let scopeIds, !scopeIds.contains(mark.conversationId) { continue }
            seenIds.insert(markId)
            items.append(RecallResult.Item(markId: mark.markId, lev: mark.lev, content: mark.content, tags: [], createdAt: mark.createdAt))
        }
        return items
    }

    private func generateSearchId(conversationId: String) -> String {
        let prefix = String(conversationId.prefix(3))
        let random = String(format: "%07x", Int.random(in: 0...0xFFFFFFF))
        return "recall-\(prefix)-\(random)"
    }
}
