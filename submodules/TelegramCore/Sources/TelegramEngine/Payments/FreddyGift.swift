import Foundation
import Postbox

public enum FreddyGift {
    // Private local IDs, deliberately outside Telegram's catalog.
    public static let id: Int64 = -7102920260060
    public static let resourceId: Int64 = LocalCommandGift.freddy.resourceId
    public static let displayStars: Int64 = 43

    public static func isPersonalChat(_ peerId: EnginePeer.Id) -> Bool {
        return peerId.namespace == Namespaces.Peer.CloudUser
    }

    public static func isFile(_ file: TelegramMediaFile) -> Bool {
        return file.fileId.namespace == Namespaces.Media.LocalFile && LocalCommandGift.all.contains(where: { $0.id == file.fileId.id })
    }

    /// Render-only projection: preserves Telegram identity and read state.
    /// The original command stays in Postbox; no message is deleted or sent.
    public static func incomingMessage(_ message: EngineMessage, gift: StarGift, accountPeerId: EnginePeer.Id) -> EngineMessage {
        let raw = message._asMessage()
        guard raw.id.namespace == Namespaces.Message.Cloud, raw.id.peerId != accountPeerId,
              FreddyCommand.shouldReplaceIncoming(text: raw.text, isIncoming: raw.flags.contains(.Incoming),
                isPersonalChat: isPersonalChat(raw.id.peerId), hasMedia: !raw.media.isEmpty,
                isForwarded: raw.forwardInfo != nil, authorMatchesChat: raw.author?.id == raw.id.peerId),
              let command = FreddyCommand.parse(raw.text),
              case let .generic(value) = gift, value.id == command.gift.id,
              isFile(value.file) else { return message }
        let caption: String? = command.caption.isEmpty ? nil : command.caption
        let action = TelegramMediaAction(action: .starGift(
            gift: gift, convertStars: command.gift.stars, text: caption, entities: caption == nil ? nil : [],
            nameHidden: false, savedToProfile: false, converted: false, upgraded: false,
            canUpgrade: false, upgradeStars: nil, isRefunded: false, isPrepaidUpgrade: false,
            upgradeMessageId: nil, peerId: nil, senderId: raw.author?.id, savedId: nil,
            prepaidUpgradeHash: nil, giftMessageId: nil, upgradeSeparate: false,
            isAuctionAcquired: false, toPeerId: accountPeerId, number: nil
        ))
        return EngineMessage(raw.withUpdatedText("").withUpdatedMedia([action]))
    }

    public static func make(account: Account, data: Data, definition: LocalCommandGift = .freddy) -> StarGift {
        let resource = LocalFileMediaResource(fileId: definition.resourceId)
        account.postbox.mediaBox.storeResourceData(resource.id, data: data, synchronous: true)
        let file = TelegramMediaFile(
            fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: definition.id), partialReference: nil,
            resource: resource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil,
            mimeType: definition.mimeType, size: Int64(data.count),
            attributes: [.FileName(fileName: definition.resourceName + "." + definition.resourceExtension), .Animated,
                         .ImageSize(size: PixelDimensions(width: 512, height: 512)),
                         .Sticker(displayText: "🎁", packReference: nil, maskData: nil)],
            alternativeRepresentations: []
        )
        return .generic(StarGift.Gift(
            id: definition.id, title: definition.title, file: file, price: definition.price ?? definition.stars, convertStars: definition.stars,
            availability: nil, soldOut: nil, flags: [], upgradeStars: nil, releasedBy: nil,
            perUserLimit: nil, lockedUntilDate: nil, auctionSlug: nil, auctionGiftsPerRound: nil,
            auctionStartDate: nil, upgradeVariantsCount: nil, background: nil
        ))
    }
}
