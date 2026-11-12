import Foundation

/// Private chat-only artwork, deliberately separate from the Telegram gift catalog.
public struct LocalCommandGift: Equatable {
    public let id: Int64
    public let title: String
    public let aliases: [String]
    public let resourceName: String
    public let resourceExtension: String
    public let stars: Int64
    public var price: Int64? = nil

    public var resourceId: Int64 { return self.id - 1 }
    public var mimeType: String { return self.resourceExtension == "tgs" ? "application/x-tgsticker" : "video/webm" }

    public static let freddy = LocalCommandGift(id: -7102920260060, title: "Freddy · Halloween", aliases: ["/freddy", "/halloween", "/фреди", "/фредди"], resourceName: "FreddyHalloween60", resourceExtension: "webm", stars: 43)
    public static let all: [LocalCommandGift] = [
        freddy,
        LocalCommandGift(id: -7102920260100, title: "Кибертрак", aliases: ["/кибертрак", "/cybertruck"], resourceName: "ChatGiftCybertruck", resourceExtension: "tgs", stars: 5000),
        LocalCommandGift(id: -7102920260110, title: "Молоток", aliases: ["/молоток", "/hammer"], resourceName: "ChatGiftHammer", resourceExtension: "tgs", stars: 500),
        LocalCommandGift(id: -7102920260120, title: "Золотой крест", aliases: ["/крест", "/cross"], resourceName: "ChatGiftCross", resourceExtension: "tgs", stars: 2500),
        LocalCommandGift(id: -7102920260130, title: "Снеговик", aliases: ["/снеговик", "/snowman"], resourceName: "ChatGiftSnowman", resourceExtension: "tgs", stars: 1000),
        LocalCommandGift(id: -7102920260140, title: "Пряник", aliases: ["/пряник", "/gingerbread"], resourceName: "ChatGiftGingerbread", resourceExtension: "tgs", stars: 500),
        LocalCommandGift(id: -7102920260150, title: "Тедди", aliases: ["/тедди", "/teddy"], resourceName: "ChatGiftTeddy", resourceExtension: "tgs", stars: 2500),
        LocalCommandGift(id: -7102920260160, title: "Какао", aliases: ["/какао", "/cocoa"], resourceName: "ChatGiftCocoa", resourceExtension: "tgs", stars: 100),
        LocalCommandGift(id: -7102920260170, title: "Звёздочка", aliases: ["/звезда", "/star"], resourceName: "ChatGiftStar", resourceExtension: "tgs", stars: 1000),
        LocalCommandGift(id: -7102920260180, title: "Молоко с печеньем", aliases: ["/печенье", "/cookie"], resourceName: "ChatGiftCookie", resourceExtension: "tgs", stars: 100),
        LocalCommandGift(id: -7102920260200, title: "Кубок", aliases: ["/кубок", "/трофей", "/cup"], resourceName: "ChatGiftCup", resourceExtension: "tgs", stars: 85, price: 100),
        LocalCommandGift(id: -7102920260210, title: "Роза", aliases: ["/роза", "/rose"], resourceName: "ChatGiftRose", resourceExtension: "tgs", stars: 21, price: 25),
        LocalCommandGift(id: -7102920260220, title: "Торт", aliases: ["/торт", "/cake"], resourceName: "ChatGiftCake", resourceExtension: "tgs", stars: 43, price: 50),
        LocalCommandGift(id: -7102920260230, title: "Сердце", aliases: ["/сердце", "/heart"], resourceName: "ChatGiftHeart", resourceExtension: "tgs", stars: 13, price: 15),
        LocalCommandGift(id: -7102920260240, title: "Мишка", aliases: ["/мишка", "/медведь", "/bear"], resourceName: "ChatGiftBear", resourceExtension: "tgs", stars: 13, price: 15),
        LocalCommandGift(id: -7102920260250, title: "Подарок", aliases: ["/подарок", "/present"], resourceName: "ChatGiftPresent", resourceExtension: "tgs", stars: 21, price: 25),
        LocalCommandGift(id: -7102920260260, title: "Букет", aliases: ["/букет", "/цветы", "/bouquet"], resourceName: "ChatGiftBouquet", resourceExtension: "tgs", stars: 43, price: 50),
        LocalCommandGift(id: -7102920260270, title: "Алмаз", aliases: ["/алмаз", "/бриллиант", "/diamond"], resourceName: "ChatGiftDiamond", resourceExtension: "tgs", stars: 85, price: 100),
        LocalCommandGift(id: -7102920260280, title: "Ракета", aliases: ["/ракета", "/rocket"], resourceName: "ChatGiftRocket", resourceExtension: "tgs", stars: 43, price: 50),
        LocalCommandGift(id: -7102920260290, title: "Кольцо", aliases: ["/кольцо", "/ring"], resourceName: "ChatGiftRing", resourceExtension: "tgs", stars: 85, price: 100),
        LocalCommandGift(id: -7102920260300, title: "Шампанское", aliases: ["/шампанское", "/champagne"], resourceName: "ChatGiftChampagne", resourceExtension: "tgs", stars: 43, price: 50)
    ]
}

/// Animation commands displayed locally; no catalog purchase or Stars transaction.
public struct FreddyCommand: Equatable {
    public let caption: String
    public let gift: LocalCommandGift

    public static func parse(_ text: String) -> FreddyCommand? {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
        guard let first = parts.first,
              let gift = LocalCommandGift.all.first(where: { $0.aliases.contains(first.lowercased()) }) else { return nil }
        let caption = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
        return FreddyCommand(caption: String(caption.prefix(1024)), gift: gift)
    }
    public static func shouldReplaceIncoming(text: String, isIncoming: Bool, isPersonalChat: Bool, hasMedia: Bool, isForwarded: Bool, authorMatchesChat: Bool) -> Bool {
        return isIncoming && isPersonalChat && !hasMedia && !isForwarded && authorMatchesChat && parse(text) != nil
    }
}

public enum VisualLogoutCommand {
    public static func matches(_ text: String) -> Bool {
        return text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "/:снос"
    }
}
