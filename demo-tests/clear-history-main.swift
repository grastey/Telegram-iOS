import Foundation

let account: Int64 = -990001
let peer: Int64 = 990002
let other: Int64 = 990003
let prefix = "ghostgram.sync.\(account)."
func cleanup() {
    for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
cleanup()
defer { cleanup() }
let pending = GhostGramGiftSubmission(recipient: String(peer), gift: .init(regularId: 123), comment: "pending")
let untouched = GhostGramGiftSubmission(recipient: String(other), gift: .init(regularId: 123), comment: "keep")
precondition(GhostGramSyncStorage.enqueue(accountId: account, submission: pending))
precondition(GhostGramSyncStorage.enqueue(accountId: account, submission: untouched))
GhostGramSyncStorage.clearChat(accountId: account, peerId: peer, messageIds: [11], timestamp: 100)
precondition(GhostGramSyncStorage.pending(accountId: account) == [untouched])
// Old replay, in-flight response and a queued send acknowledged after clearing.
precondition(GhostGramSyncStorage.wasCleared(accountId: account, peerId: peer, messageId: 22, timestamp: 99))
precondition(GhostGramSyncStorage.wasCleared(accountId: account, peerId: peer, messageId: 11, timestamp: 200))
let pendingId = GhostGramSyncStorage.messageUniqueId(sender: String(account), clientId: pending.client_id)
precondition(GhostGramSyncStorage.wasCleared(accountId: account, peerId: peer, messageId: pendingId, timestamp: 200))
// New gifts and other chats/accounts must remain eligible.
precondition(!GhostGramSyncStorage.wasCleared(accountId: account, peerId: peer, messageId: 33, timestamp: 101))
precondition(!GhostGramSyncStorage.wasCleared(accountId: account, peerId: other, messageId: 11, timestamp: 99))
precondition(!GhostGramSyncStorage.wasCleared(accountId: account - 1, peerId: peer, messageId: 11, timestamp: 99))
GhostGramSyncStorage.clearChat(accountId: account, peerId: peer, messageIds: [44], timestamp: 300)
precondition(GhostGramSyncStorage.wasCleared(accountId: account, peerId: peer, messageId: 11, timestamp: 400))
precondition(GhostGramSyncStorage.wasCleared(accountId: account, peerId: peer, messageId: 44, timestamp: 400))
print("PASS: cleared history survives replays, pending echoes and repeated clears; new gifts and other chats are preserved")
