import Foundation
import Postbox

public enum FreddyGift {
    // Private local IDs, deliberately outside Telegram's catalog.
    public static let id: Int64 = -7102920260060
    public static let resourceId: Int64 = -7102920260061
    public static let displayStars: Int64 = 43

    public static func isPersonalChat(_ peerId: EnginePeer.Id) -> Bool {
        return peerId.namespace == Namespaces.Peer.CloudUser
    }

    public static func isFile(_ file: TelegramMediaFile) -> Bool {
        return file.fileId.namespace == Namespaces.Media.LocalFile && file.fileId.id == id
    }

    /// Render-only projection: preserves Telegram identity and read state.
    /// The original command stays in Postbox; no message is deleted or sent.
    public static func incomingMessage(_ message: EngineMessage, gift: StarGift, accountPeerId: EnginePeer.Id) -> EngineMessage {
        let raw = message._asMessage()
        guard raw.id.namespace == Namespaces.Message.Cloud, raw.id.peerId != accountPeerId,
              FreddyCommand.shouldReplaceIncoming(text: raw.text, isIncoming: raw.flags.contains(.Incoming),
                isPersonalChat: isPersonalChat(raw.id.peerId), hasMedia: !raw.media.isEmpty,
                isForwarded: raw.forwardInfo != nil, authorMatchesChat: raw.author?.id == raw.id.peerId),
              let command = FreddyCommand.parse(raw.text) else { return message }
        let caption: String? = command.caption.isEmpty ? nil : command.caption
        let action = TelegramMediaAction(action: .starGift(
            gift: gift, convertStars: displayStars, text: caption, entities: caption == nil ? nil : [],
            nameHidden: false, savedToProfile: false, converted: false, upgraded: false,
            canUpgrade: false, upgradeStars: nil, isRefunded: false, isPrepaidUpgrade: false,
            upgradeMessageId: nil, peerId: nil, senderId: raw.author?.id, savedId: nil,
            prepaidUpgradeHash: nil, giftMessageId: nil, upgradeSeparate: false,
            isAuctionAcquired: false, toPeerId: accountPeerId, number: nil
        ))
        return EngineMessage(raw.withUpdatedText("").withUpdatedMedia([action]))
    }

    public static func make(account: Account, data: Data) -> StarGift {
        let resource = LocalFileMediaResource(fileId: resourceId)
        account.postbox.mediaBox.storeResourceData(resource.id, data: data, synchronous: true)
        let file = TelegramMediaFile(
            fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: id), partialReference: nil,
            resource: resource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil,
            mimeType: "video/webm", size: Int64(data.count),
            attributes: [.FileName(fileName: "FreddyHalloween60.webm"), .Animated,
                         .ImageSize(size: PixelDimensions(width: 512, height: 512)),
                         .Sticker(displayText: "рџЋѓ", packReference: nil, maskData: nil)],
            alternativeRepresentations: []
        )
        return .generic(StarGift.Gift(
            id: id, title: "Freddy вЂў Halloween", file: file, price: displayStars, convertStars: displayStars,
            availability: nil, soldOut: nil, flags: [], upgradeStars: nil, releasedBy: nil,
            perUserLimit: nil, lockedUntilDate: nil, auctionSlug: nil, auctionGiftsPerRound: nil,
            auctionStartDate: nil, upgradeVariantsCount: nil, background: nil
        ))
    }
}
