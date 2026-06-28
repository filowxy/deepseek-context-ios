import Foundation

/// Parsed XML tag action emitted by the AI.
enum XMLTagAction: Equatable {
    struct MarkPayload: Equatable {
        let type: MarkType
        let lev: Int
        let content: String
        let tags: [String]
        let idemKey: String
    }

    struct DeletePayload: Equatable {
        let markId: Int64
    }

    struct RecoverPayload: Equatable {
        let markId: Int64
    }

    struct RecallPayload: Equatable {
        let query: String
        let scope: RecallScope
    }

    struct AllPayload: Equatable {
        let type: String
        let searchId: String
    }

    struct SearchPayload: Equatable {
        let query: String
        let depth: String
    }

    struct OpenPayload: Equatable {
        let url: String
    }

    struct CallSkillPayload: Equatable {
        let name: String
    }

    struct GlobalSuggestPayload: Equatable {
        let content: String
        let reason: String?
    }

    case mark(MarkPayload)
    case delete(DeletePayload)
    case recover(RecoverPayload)
    case recall(RecallPayload)
    case all(AllPayload)
    case search(SearchPayload)
    case open(OpenPayload)
    case callSkill(CallSkillPayload)
    case globalSuggest(GlobalSuggestPayload)
}

enum XMLTagParserError: Error {
    case invalidJSON
    case missingField(String)
    case invalidLevel
    case invalidType
}

/// Extracts structured actions from AI output.
struct XMLTagParser {

    /// Parses all supported XML tags in the given text.
    static func parse(_ text: String) -> [XMLTagAction] {
        var actions: [XMLTagAction] = []
        actions.append(contentsOf: parseMarks(text))
        actions.append(contentsOf: parseDeletes(text))
        actions.append(contentsOf: parseRecovers(text))
        actions.append(contentsOf: parseRecalls(text))
        actions.append(contentsOf: parseAlls(text))
        actions.append(contentsOf: parseSearches(text))
        actions.append(contentsOf: parseOpens(text))
        actions.append(contentsOf: parseCallSkills(text))
        actions.append(contentsOf: parseGlobalSuggests(text))
        return actions
    }

    /// Strips all recognized XML tags from the text, returning clean display content.
    static func stripTags(_ text: String) -> String {
        let pattern = #"<(main|de-main|recover-mark|recall-context|all|search|open|call-skill|global-suggest)[^>]*>.*?<\/\1>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Individual tag parsers

    private static func parseMarks(_ text: String) -> [XMLTagAction] {
        extractTag(text, tag: "main").compactMap { payload in
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }
            guard let typeRaw = json["type"] as? String,
                  let type = MarkType(rawValue: typeRaw),
                  let lev = json["lev"] as? Int,
                  (0...3).contains(lev),
                  let content = json["content"] as? String,
                  !content.isEmpty,
                  let idemKey = json["idem_key"] as? String else {
                return nil
            }
            let tags = (json["tags"] as? [String]) ?? []
            return .mark(.init(type: type, lev: lev, content: content, tags: tags, idemKey: idemKey))
        }
    }

    private static func parseDeletes(_ text: String) -> [XMLTagAction] {
        extractTag(text, tag: "de-main").compactMap { payload in
            guard let id = extractId(payload) else { return nil }
            return .delete(.init(markId: id))
        }
    }

    private static func parseRecovers(_ text: String) -> [XMLTagAction] {
        extractTag(text, tag: "recover-mark").compactMap { payload in
            guard let id = extractId(payload) else { return nil }
            return .recover(.init(markId: id))
        }
    }

    private static func parseRecalls(_ text: String) -> [XMLTagAction] {
        extractTag(text, tag: "recall-context").compactMap { payload in
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let queryDict = json["query"] as? [String: Any],
                  let query = queryDict["search"] as? String else {
                return nil
            }
            let scopeRaw = queryDict["scope"] as? String ?? "current"
            let scope = RecallScope(rawValue: scopeRaw) ?? .current
            return .recall(.init(query: query, scope: scope))
        }
    }

    private static func parseAlls(_ text: String) -> [XMLTagAction] {
        extractTag(text, tag: "all").compactMap { payload in
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String,
                  let searchId = json["searchinfo"] as? String else {
                return nil
            }
            return .all(.init(type: type, searchId: searchId))
        }
    }

    private static func parseSearches(_ text: String) -> [XMLTagAction] {
        extractTag(text, tag: "search").compactMap { payload in
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let query = json["q"] as? String else {
                return nil
            }
            let depth = json["depth"] as? String ?? "normal"
            return .search(.init(query: query, depth: depth))
        }
    }

    private static func parseOpens(_ text: String) -> [XMLTagAction] {
        extractTag(text, tag: "open").compactMap { payload in
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let url = json["dis"] as? String else {
                return nil
            }
            return .open(.init(url: url))
        }
    }

    private static func parseCallSkills(_ text: String) -> [XMLTagAction] {
        extractTag(text, tag: "call-skill", isRaw: true).compactMap { payload in
            // Format: name:'审查输出'
            let pattern = #"name:\s*'([^']+)'"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: payload, range: NSRange(payload.startIndex..., in: payload)),
                  let range = Range(match.range(at: 1), in: payload) else {
                return nil
            }
            return .callSkill(.init(name: String(payload[range])))
        }
    }

    private static func parseGlobalSuggests(_ text: String) -> [XMLTagAction] {
        extractTag(text, tag: "global-suggest").compactMap { payload in
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = json["content"] as? String else {
                return nil
            }
            return .globalSuggest(.init(content: content, reason: json["reason"] as? String))
        }
    }

    // MARK: - Helpers

    private static func extractTag(_ text: String, tag: String, isRaw: Bool = false) -> [String] {
        let pattern = #"<"# + NSRegularExpression.escapedPattern(for: tag) + #"[^>]*>(.*?)<\/"# + NSRegularExpression.escapedPattern(for: tag) + #">"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard let contentRange = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func extractId(_ payload: String) -> Int64? {
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? Int64 else {
            return nil
        }
        return id
    }
}
