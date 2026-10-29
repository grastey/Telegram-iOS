import Foundation
import UIKit
import SwiftSignalKit
import Display
import TelegramCore
import TelegramPresentationData
import AlertUI
import AppBundle
import ChatInterfaceState
import ChatPresentationInterfaceState
import ChatControllerInteraction

extension ChatControllerImpl {
    @discardableResult
    func handleFreddyCommand(_ messages: [EnqueueMessage]) -> Bool {
        guard DemoWallet.isEnabled, messages.count == 1,
              case let .message(text, _, _, mediaReference, _, _, _, _, _, _) = messages[0],
              mediaReference == nil, let command = FreddyCommand.parse(text) else { return false }
        guard case let .peer(peerId) = self.chatLocation, FreddyGift.isPersonalChat(peerId),
              self.presentationInterfaceState.interfaceState.editMessage == nil else {
            self.present(textAlertController(context: self.context, title: "Freddy", text: "РљРѕРјР°РЅРґР° РґРѕСЃС‚СѓРїРЅР° РІ Р»РёС‡РЅРѕРј С‡Р°С‚Рµ.", actions: [TextAlertAction(type: .defaultAction, title: "OK", action: {})]), in: .window(.root))
            return true
        }
        guard let path = getAppBundle().path(forResource: "FreddyHalloween60", ofType: "webm"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)), !data.isEmpty else {
            self.present(textAlertController(context: self.context, title: "Freddy", text: "РќРµ РЅР°Р№РґРµРЅ С„Р°Р№Р» Р°РЅРёРјР°С†РёРё. РџРµСЂРµСѓСЃС‚Р°РЅРѕРІРё РїРѕСЃР»РµРґРЅСЋСЋ СЃР±РѕСЂРєСѓ РјРѕРґР°.", actions: [TextAlertAction(type: .defaultAction, title: "OK", action: {})]), in: .window(.root))
            return true
        }
        let gift = FreddyGift.make(account: self.context.account, data: data)
        self.hintPlayNextOutgoingGift()
        self.updateChatPresentationInterfaceState(animated: false, interactive: false) { state in
            state.updatedInterfaceState { $0.withUpdatedReplyMessageSubject(nil).withUpdatedComposeInputState(ChatTextInputState(inputText: NSAttributedString())) }
        }
        let _ = (addLocalDemoGift(account: self.context.account, peerId: peerId, gift: gift, text: command.caption, synchronize: false)
        |> deliverOnMainQueue).startStandalone()
        return true
    }
}
