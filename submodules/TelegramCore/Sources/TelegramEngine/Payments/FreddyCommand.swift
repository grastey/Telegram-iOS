import Foundation

/// Local animation commands: never submitted to Telegram or the gift catalog.
public struct FreddyCommand: Equatable {
    public let caption: String

    public static func parse(_ text: String) -> FreddyCommand? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
        guard let first = parts.first, ["/freddy", "/halloween"].contains(first.lowercased()) else { return nil }
        let caption = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return FreddyCommand(caption: String(caption.prefix(1024)))
    }
}
