import Foundation
import UIKit
import TelegramCore

func presentDemoWalletEditor(controller: UIViewController, accountId: Int64, syncAccountId: Int64, completion: @escaping () -> Void) {
    let wallet = DemoWallet.load(accountId: accountId)
    let configured = GhostGramSyncStorage.token(accountId: syncAccountId) != nil
    let pending = GhostGramSyncStorage.pending(accountId: syncAccountId).count
    let alert = UIAlertController(title: "Баланс", message: "Telegram ID: \(syncAccountId)\nСинхронизация: \(configured ? "включена" : "выключена"). В очереди: \(pending)", preferredStyle: .alert)
    alert.addTextField { field in
        field.placeholder = "Stars"
        field.keyboardType = .numberPad
        field.text = String(wallet.stars)
    }
    alert.addTextField { field in
        field.placeholder = "TON"
        field.keyboardType = .decimalPad
        field.text = wallet.tonText
    }
    alert.addTextField { field in
        field.placeholder = "Новый ключ синхронизации (необязательно)"
        field.isSecureTextEntry = true
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
    }
    if configured {
        alert.addAction(UIAlertAction(title: "Отключить синхронизацию", style: .destructive, handler: { _ in
            let _ = GhostGramSyncStorage.saveToken(accountId: syncAccountId, token: nil)
            completion()
        }))
    }
    alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
    let fields = alert.textFields ?? []
    alert.addAction(UIAlertAction(title: "Сохранить", style: .default, handler: { [weak controller] _ in
        guard fields.count == 3 else { return }
        let starsText = fields[0].text ?? ""
        guard let stars = Int64(starsText), stars >= 0, stars <= 1_000_000_000_000,
              starsText.allSatisfy({ $0.isASCII && $0.isNumber }),
              let ton = DemoWallet.parseTon(fields[1].text ?? "") else {
            let error = UIAlertController(title: "Проверь числа", message: "Stars: от 0 до 1 000 000 000 000. TON: от 0 до 1 000 000 000, до 9 знаков после запятой.", preferredStyle: .alert)
            error.addAction(UIAlertAction(title: "OK", style: .default))
            controller?.present(error, animated: true)
            return
        }
        let token = fields[2].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let save = {
            DemoWallet(stars: stars, tonNanograms: ton).save(accountId: accountId)
            completion()
        }
        if token.isEmpty {
            save()
        } else {
            GhostGramSyncManager.verify(token: token, accountId: syncAccountId, completion: { valid in
                let status = valid ? GhostGramSyncStorage.saveTokenStatus(accountId: syncAccountId, token: token) : nil
                if status == 0 {
                    save()
                } else {
                    let message = status.map { "Ключ проверен сервером, но iOS не сохранила его. Код: \($0)." }
                        ?? "Ключ не прошёл проверку для Telegram ID \(syncAccountId). Проверь ключ и подключение к сети."
                    let error = UIAlertController(title: "Не удалось подключить", message: message, preferredStyle: .alert)
                    error.addAction(UIAlertAction(title: "OK", style: .default))
                    controller?.present(error, animated: true)
                }
            })
        }
    }))
    controller.present(alert, animated: true)
}
