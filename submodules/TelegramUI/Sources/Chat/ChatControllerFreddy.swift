import Foundation
import UIKit
import SwiftSignalKit
import Display
import TelegramCore
import AccountContext
import PresentationDataUtils
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
            self.present(textAlertController(context: self.context, title: command.gift.title, text: "Команда доступна только в личном чате.", actions: [TextAlertAction(type: .defaultAction, title: "OK", action: {})]), in: .window(.root))
            return true
        }
        guard let path = getAppBundle().path(forResource: command.gift.resourceName, ofType: command.gift.resourceExtension),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)), !data.isEmpty else {
            self.present(textAlertController(context: self.context, title: command.gift.title, text: "Не найден файл анимации. Установите последнюю сборку клиента.", actions: [TextAlertAction(type: .defaultAction, title: "OK", action: {})]), in: .window(.root))
            return true
        }
        let gift = FreddyGift.make(account: self.context.account, data: data, definition: command.gift)
        self.hintPlayNextOutgoingGift()
        self.updateChatPresentationInterfaceState(animated: false, interactive: false) { state in
            state.updatedInterfaceState { $0.withUpdatedReplyMessageSubject(nil).withUpdatedComposeInputState(ChatTextInputState(inputText: NSAttributedString())) }
        }
        let _ = (addLocalDemoGift(account: self.context.account, peerId: peerId, gift: gift, text: command.caption, synchronize: false)
        |> deliverOnMainQueue).startStandalone()
        return true
    }
}
