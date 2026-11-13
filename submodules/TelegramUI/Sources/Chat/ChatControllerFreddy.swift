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

extension ChatControllerImpl {
    func showVisualLogout(message: EngineMessage) {
        guard self.isViewLoaded, self.view.window != nil, self.visualLogoutCover == nil,
              case let .peer(peerId) = self.chatLocation, peerId == message.id.peerId else { return }
        let key = "ghostgram.visualLogout.\(self.context.account.peerId.toInt64()).\(peerId.toInt64()).\(message.id.id)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        self.view.endEditing(true)
        let cover = UIView(frame: self.view.bounds)
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cover.backgroundColor = .systemBackground
        cover.accessibilityViewIsModal = true
        let back = UIButton(type: .system)
        back.setTitle("‹ Назад", for: .normal)
        back.titleLabel?.font = .systemFont(ofSize: 18)
        back.addAction(UIAction { [weak self, weak cover] _ in
            cover?.removeFromSuperview()
            self?.visualLogoutCover = nil
        }, for: .touchUpInside)
        let icon = UIImageView(image: UIImage(systemName: "person.crop.circle.badge.xmark"))
        icon.contentMode = .scaleAspectFit
        icon.tintColor = .systemBlue
        let title = UILabel()
        title.text = "Вы вышли из аккаунта"
        title.font = .boldSystemFont(ofSize: 25)
        title.textAlignment = .center
        title.numberOfLines = 0
        let detail = UILabel()
        detail.text = "Нажмите «Назад», чтобы вернуться в диалог."
        detail.font = .systemFont(ofSize: 17)
        detail.textColor = .secondaryLabel
        detail.numberOfLines = 0
        detail.textAlignment = .center
        let stack = UIStackView(arrangedSubviews: [icon, title, detail])
        stack.axis = .vertical
        stack.spacing = 24
        for child in [back, stack] {
            child.translatesAutoresizingMaskIntoConstraints = false
            cover.addSubview(child)
        }
        NSLayoutConstraint.activate([
            back.leadingAnchor.constraint(equalTo: cover.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            back.topAnchor.constraint(equalTo: cover.safeAreaLayoutGuide.topAnchor, constant: 8),
            back.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            stack.centerYAnchor.constraint(equalTo: cover.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: cover.safeAreaLayoutGuide.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: cover.safeAreaLayoutGuide.trailingAnchor, constant: -28),
            icon.heightAnchor.constraint(equalToConstant: 96)
        ])
        self.visualLogoutCover = cover
        self.view.addSubview(cover)
        cover.alpha = 0
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.25) { cover.alpha = 1 }
    }
}
