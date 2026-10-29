import Foundation
import Postbox

public enum FreddyGift {
    // Private local IDs, deliberately outside Telegram's catalog.
    public static let id: Int64 = -7102920260060
    public static let resourceId: Int64 = -7102920260061

    public static func isPersonalChat(_ peerId: EnginePeer.Id) -> Bool {
        return peerId.namespace == Namespaces.Peer.CloudUser
    }

    public static func isFile(_ file: TelegramMediaFile) -> Bool {
        return file.fileId.namespace == Namespaces.Media.LocalFile && file.fileId.id == id
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
            id: id, title: "Freddy вЂў Halloween", file: file, price: 0, convertStars: 0,
            availability: nil, soldOut: nil, flags: [], upgradeStars: nil, releasedBy: nil,
            perUserLimit: nil, lockedUntilDate: nil, auctionSlug: nil, auctionGiftsPerRound: nil,
            auctionStartDate: nil, upgradeVariantsCount: nil, background: nil
        ))
    }
}
