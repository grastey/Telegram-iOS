import Foundation

/// Animation commands displayed locally; no catalog purchase or Stars transaction.
public struct FreddyCommand: Equatable {
    public let caption: String

    public static func parse(_ text: String) -> FreddyCommand? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
        guard let first = parts.first, ["/freddy", "/halloween", "/фреди", "/фредди"].contains(first.lowercased()) else { return nil }
        let caption = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return FreddyCommand(caption: String(caption.prefix(1024)))
    }
    public static func shouldReplaceIncoming(text: String, isIncoming: Bool, isPersonalChat: Bool, hasMedia: Bool, isForwarded: Bool, authorMatchesChat: Bool) -> Bool {
        return isIncoming && isPersonalChat && !hasMedia && !isForwarded && authorMatchesChat && parse(text) != nil
    }
}

