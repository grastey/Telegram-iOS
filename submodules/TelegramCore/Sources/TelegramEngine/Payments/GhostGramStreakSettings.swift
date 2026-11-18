import Foundation
import Postbox
import SwiftSignalKit

public enum GhostGramStreakSettings {
    public static func isEnabled(accountId: Int64) -> Bool {
        return UserDefaults.standard.bool(forKey: "GhostGram.streak.enabled.\(accountId)")
    }

    public static func setEnabled(_ value: Bool, accountId: Int64) {
        UserDefaults.standard.set(value, forKey: "GhostGram.streak.enabled.\(accountId)")
    }

    public static func activity(account: Account, peerId: EnginePeer.Id, since day: Date) -> Signal<(incoming: Bool, outgoing: Bool), NoError> {
        return account.viewTracker.aroundMessageHistoryViewForLocation(
            .peer(peerId: peerId, threadId: nil), index: .upperBound, anchorIndex: .upperBound, count: 120
        )
        |> filter { view, _, _ in !view.isLoading }
        |> map { view, _, _ in
            var incoming = false
            var outgoing = false
            for entry in view.entries.reversed() {
                let message = entry.message
                if Date(timeIntervalSince1970: TimeInterval(message.timestamp)) < day { break }
                guard message.id.namespace == Namespaces.Message.Cloud,
                      message.flags.intersection([.Unsent, .Sending, .Failed]).isEmpty,
                      !message.media.contains(where: { $0 is TelegramMediaAction }) else { continue }
                if message.effectivelyIncoming(account.peerId) {
                    incoming = true
                } else {
                    outgoing = true
                }
                if incoming && outgoing { break }
            }
            return (incoming, outgoing)
        }
    }
}
