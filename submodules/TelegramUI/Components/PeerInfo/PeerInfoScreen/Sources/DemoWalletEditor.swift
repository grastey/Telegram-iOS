import Foundation
import UIKit
import TelegramCore

func presentDemoWalletEditor(controller: UIViewController, accountId: Int64, completion: @escaping () -> Void) {
    let wallet = DemoWallet.load(accountId: accountId)
    let alert = UIAlertController(title: "Демо-балансы", message: "Только на этом устройстве. Реальные Stars и TON не меняются.", preferredStyle: .alert)
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
    alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
    alert.addAction(UIAlertAction(title: "Сохранить", style: .default, handler: { [weak alert, weak controller] _ in
        guard let fields = alert?.textFields else { return }
        let starsText = fields[0].text ?? ""
        guard let stars = Int64(starsText), stars >= 0, stars <= 1_000_000_000_000,
              starsText.allSatisfy({ $0.isASCII && $0.isNumber }),
              let ton = DemoWallet.parseTon(fields[1].text ?? "") else {
            let error = UIAlertController(title: "Проверь числа", message: "Stars: от 0 до 1 000 000 000 000. TON: от 0 до 1 000 000 000, до 9 знаков после запятой.", preferredStyle: .alert)
            error.addAction(UIAlertAction(title: "OK", style: .default))
            controller?.present(error, animated: true)
            return
        }
        DemoWallet(stars: stars, tonNanograms: ton).save(accountId: accountId)
        completion()
    }))
    controller.present(alert, animated: true)
}
