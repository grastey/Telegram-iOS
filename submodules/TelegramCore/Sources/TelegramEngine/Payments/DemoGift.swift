import Foundation
import Postbox
import SwiftSignalKit

/// Inserts a local service card without entering the outgoing queue.
/// No outgoing attributes or sending flags: PendingMessageManager must never upload this.
public func addLocalDemoGift(account: Account, peerId: EnginePeer.Id, gift: StarGift, text: String, entities: [MessageTextEntity]? = nil, syncAuthorId: PeerId? = nil, syncTimestamp: Int32? = nil, syncUniqueId: Int64? = nil, synchronize: Bool = true) -> Signal<Void, NoError> {
    guard DemoWallet.isEnabled, peerId.namespace == Namespaces.Peer.CloudUser else {
        return .complete()
    }
    let authorId = syncAuthorId ?? account.peerId
    let incoming = authorId != account.peerId
    var uniqueId = syncUniqueId
    if synchronize, GhostGramSyncStorage.token(accountId: account.peerId.id._internalGetInt64Value()) != nil {
        let reference: GhostGramGiftReference
        switch gift {
        case let .generic(value): reference = GhostGramGiftReference(regularId: value.id)
        case let .unique(value): reference = GhostGramGiftReference(collectibleSlug: value.slug)
        }
        let submission = GhostGramGiftSubmission(recipient: String(peerId.id._internalGetInt64Value()), gift: reference, comment: text)
        if text.unicodeScalars.count <= 1024, GhostGramSyncStorage.enqueue(accountId: account.peerId.id._internalGetInt64Value(), submission: submission) {
            uniqueId = GhostGramSyncStorage.messageUniqueId(sender: String(account.peerId.id._internalGetInt64Value()), clientId: submission.client_id)
        }
    }
    let finalUniqueId = uniqueId
    return account.postbox.transaction { transaction -> Void in
        if let finalUniqueId, transaction.messageIdForGloballyUniqueMessageId(peerId: peerId, id: finalUniqueId) != nil { return }
        let caption: String? = text.isEmpty ? nil : text
        // Postbox persists gift text only together with its entity array.
        let captionEntities: [MessageTextEntity]? = caption == nil ? nil : (entities ?? [])
        let actionType: TelegramMediaActionType
        switch gift {
        case let .generic(genericGift):
            actionType = .starGift(
                gift: gift, convertStars: genericGift.convertStars,
                text: caption,
                entities: captionEntities, nameHidden: false, savedToProfile: false, converted: false,
                upgraded: false, canUpgrade: false, upgradeStars: nil, isRefunded: false,
                isPrepaidUpgrade: false, upgradeMessageId: nil, peerId: nil,
                senderId: incoming ? authorId : nil, savedId: nil, prepaidUpgradeHash: nil,
                giftMessageId: nil, upgradeSeparate: false, isAuctionAcquired: false,
                toPeerId: incoming ? account.peerId : peerId, number: nil
            )
        case .unique:
            actionType = .starGiftUnique(
                gift: gift, isUpgrade: false, isTransferred: true, savedToProfile: false,
                canExportDate: nil, transferStars: nil, isRefunded: false,
                isPrepaidUpgrade: false, peerId: nil, senderId: authorId,
                savedId: nil, resaleAmount: nil, canTransferDate: nil, canResaleDate: nil,
                dropOriginalDetailsStars: nil, assigned: false, fromOffer: false,
                canCraftAt: nil, isCrafted: false, text: caption, entities: captionEntities, nameHidden: false
            )
        }
        let action = TelegramMediaAction(action: actionType)
        let message = StoreMessage(
            peerId: peerId, namespace: Namespaces.Message.Local, customStableId: nil,
            globallyUniqueId: finalUniqueId, groupingKey: nil, threadId: nil,
            timestamp: syncTimestamp ?? Int32(clamping: Int64(Date().timeIntervalSince1970)),
            flags: incoming ? [.Incoming] : [], tags: [], globalTags: [], localTags: [], forwardInfo: nil,
            authorId: authorId, text: text,
            attributes: [], media: [action]
        )
        let _ = transaction.addMessages([message], location: .Random)
    }
}
