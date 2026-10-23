import Foundation

/// The relay protocol carries synthetic gift references, never payment or ownership requests.
public struct GhostGramGiftReference: Codable, Equatable {
    public let kind: String
    public let id: String?
    public let slug: String?

    public init(regularId: Int64) {
        self.kind = "regular"
        self.id = String(regularId)
        self.slug = nil
    }

    public init(collectibleSlug: String) {
        self.kind = "collectible"
        self.id = nil
        self.slug = collectibleSlug
    }
}

public struct GhostGramGiftSubmission: Codable, Equatable {
    public let client_id: String
    public let recipient: String
    public let gift: GhostGramGiftReference
    public let comment: String

    public init(clientId: String = UUID().uuidString.lowercased(), recipient: String, gift: GhostGramGiftReference, comment: String) {
        self.client_id = clientId
        self.recipient = recipient
        self.gift = gift
        self.comment = comment
    }
}

public struct GhostGramGiftEvent: Codable, Equatable {
    public let seq: Int64
    public let event_id: String
    public let client_id: String
    public let sender: String
    public let recipient: String
    public let gift: GhostGramGiftReference
    public let comment: String
    public let created: Int64
    public let synthetic: Bool

    public func belongs(to accountId: String) -> Bool {
        return self.synthetic && self.seq > 0 && (self.sender == accountId || self.recipient == accountId)
    }
}

public struct GhostGramEventPage: Codable {
    public let events: [GhostGramGiftEvent]
    public let cursor: Int64
    public let has_more: Bool
}

public struct GhostGramRelayIdentity: Codable {
    public let account: String
    public let `protocol`: Int
}
