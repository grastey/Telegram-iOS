import Foundation
import Postbox
import SwiftSignalKit

/// Inserts a clearly labelled local service card without entering the outgoing queue.
/// No outgoing attributes or sending flags: PendingMessageManager must never upload this.
public func addLocalDemoGift(account: Account, peerId: EnginePeer.Id, gift: StarGift, text: String) -> Signal<Void, NoError> {
    guard DemoWallet.isEnabled, peerId.namespace == Namespaces.Peer.CloudUser else {
        return .complete()
    }
    return account.postbox.transaction { transaction -> Void in
        let caption = "ДЕМО • Только на этом устройстве" + (text.isEmpty ? "" : "\n" + text)
        let actionType: TelegramMediaActionType
        switch gift {
        case .generic:
            actionType = .starGift(
                gift: gift, convertStars: nil,
                text: caption,
                entities: nil, nameHidden: false, savedToProfile: false, converted: false,
                upgraded: false, canUpgrade: false, upgradeStars: nil, isRefunded: false,
                isPrepaidUpgrade: false, upgradeMessageId: nil, peerId: nil,
                senderId: account.peerId, savedId: nil, prepaidUpgradeHash: nil,
                giftMessageId: nil, upgradeSeparate: false, isAuctionAcquired: false,
                toPeerId: peerId, number: nil
            )
        case .unique:
            actionType = .starGiftUnique(
                gift: gift, isUpgrade: false, isTransferred: true, savedToProfile: false,
                canExportDate: nil, transferStars: nil, isRefunded: false,
                isPrepaidUpgrade: false, peerId: nil, senderId: account.peerId,
                savedId: nil, resaleAmount: nil, canTransferDate: nil, canResaleDate: nil,
                dropOriginalDetailsStars: nil, assigned: false, fromOffer: false,
                canCraftAt: nil, isCrafted: false, text: caption, entities: nil, nameHidden: false
            )
        }
        let action = TelegramMediaAction(action: actionType)
        let message = StoreMessage(
            peerId: peerId, namespace: Namespaces.Message.Local, customStableId: nil,
            globallyUniqueId: nil, groupingKey: nil, threadId: nil,
            timestamp: Int32(clamping: Int64(Date().timeIntervalSince1970)),
            flags: [], tags: [], globalTags: [], localTags: [], forwardInfo: nil,
            authorId: account.peerId, text: "ДЕМО • Подарок не отправлен",
            attributes: [], media: [action]
        )
        let _ = transaction.addMessages([message], location: .Random)
    }
}
