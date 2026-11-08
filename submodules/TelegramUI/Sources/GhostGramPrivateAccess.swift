import Foundation
import UIKit
#if canImport(TelegramCore)
import TelegramCore
#endif

/// A native admission screen. Telegram phone numbers, OTP and passwords never go to this relay.
final class GhostGramPrivateAccess {
    static let shared = GhostGramPrivateAccess()
    private weak var host: UIWindow?
    private var cover: UIView?
    private var statusLabel: UILabel?
    private var field: UITextField?
    private var button: UIButton?
    private weak var scrollView: UIScrollView?
    private var timer: Foundation.Timer?
    private var task: URLSessionDataTask?
    private var accountId: Int64?
    private var grantedId: Int64?
    private var grantedToken: String?
    private var leaseUntil: TimeInterval = 0
    private var nextCheck: TimeInterval = 0
    private var generation = 0
    private var checking = false
    private var observers: [NSObjectProtocol] = []
    private var active = true
    private var boundId: Int64?

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    private var expectedId: Int64? {
        let value = UserDefaults.standard.object(forKey: "ghostgram.private.expectedId") as? NSNumber
        return value.flatMap { $0.int64Value > 0 ? $0.int64Value : nil }
    }

    func attach(to window: UIWindow) {
        dispatchPrecondition(condition: .onQueue(.main))
        self.host = window
        if self.timer == nil {
            self.timer = Foundation.Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
            self.observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                self?.active = true
                self?.nextCheck = 0
                self?.refresh()
            })
            self.observers.append(NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                self?.active = false
                // Cover the app switcher as well as the interactive application.
                self?.show()
            })
            self.observers.append(NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] notification in
                guard let self, let host = self.host, let scroll = self.scrollView,
                      let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
                let keyboard = host.convert(frame, from: nil)
                let overlap = max(0, host.bounds.maxY - keyboard.minY)
                scroll.contentInset.bottom = overlap
                scroll.verticalScrollIndicatorInsets.bottom = overlap
                if let field = self.field, field.isFirstResponder {
                    scroll.scrollRectToVisible(field.convert(field.bounds, to: scroll).insetBy(dx: 0, dy: -16), animated: false)
                }
            })
        }
        self.refresh()
    }

    func setAccount(_ id: Int64?) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard self.accountId != id else { return }
        self.accountId = id
        self.cover?.endEditing(true)
        self.cover?.removeFromSuperview()
        self.cover = nil
        self.boundId = nil
        self.generation += 1
        self.checking = false
        self.task?.cancel()
        self.task = nil
        self.nextCheck = 0
        if let id, id != self.grantedId { self.leaseUntil = 0 }
        self.refresh()
    }

    private func refresh() {
        guard self.active, self.host != nil else { return }
        let intended = self.accountId ?? self.expectedId
        if let intended, intended == self.grantedId, let token = self.grantedToken, self.now < self.leaseUntil {
            if self.accountId == intended && self.boundId != intended {
                GhostGramSyncStorage.setSessionToken(accountId: intended, token: token)
                self.boundId = intended
            }
            self.cover?.removeFromSuperview()
            self.cover = nil
            if self.now >= self.nextCheck && !self.checking { self.verify(token) }
            return
        }
        self.show()
        guard !self.checking, self.now >= self.nextCheck else { return }
        let token = intended == self.grantedId ? self.grantedToken : intended.flatMap { GhostGramSyncStorage.token(accountId: $0) }
        if let token { self.verify(token) }
    }

    private func label(_ text: String, size: CGFloat, weight: UIFont.Weight = .regular) -> UILabel {
        let label = UILabel()
        label.text = text; label.textColor = .white; label.numberOfLines = 0
        label.font = UIFont.systemFont(ofSize: size, weight: weight)
        return label
    }

    private func show() {
        guard let host = self.host else { return }
        if let cover = self.cover {
            host.bringSubviewToFront(cover)
            return
        }
        let cover = UIView(frame: host.bounds)
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cover.backgroundColor = UIColor(red: 17/255, green: 13/255, blue: 26/255, alpha: 1)
        cover.accessibilityViewIsModal = true
        let stack = UIStackView()
        stack.axis = .vertical; stack.spacing = 18; stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(self.label("GhostGram Private", size: 30, weight: .bold))
        stack.addArrangedSubview(self.label("Вход по личному коду", size: 22, weight: .semibold))
        stack.addArrangedSubview(self.label("Код от администратора открывает приватку и автоматически подключает синхронизацию. Он привязан к твоему Telegram-аккаунту.", size: 15))
        if let id = self.accountId { stack.addArrangedSubview(self.label("Твой Telegram ID: \(id)", size: 14)) }
        let field = UITextField()
        field.attributedPlaceholder = NSAttributedString(string: "Личный код доступа", attributes: [.foregroundColor: UIColor(white: 0.72, alpha: 1)])
        field.isSecureTextEntry = true; field.autocorrectionType = .no; field.autocapitalizationType = .none
        field.textColor = .white; field.borderStyle = .roundedRect
        field.tintColor = .white; field.keyboardType = .asciiCapable; field.returnKeyType = .go
        field.addTarget(self, action: #selector(self.submit), for: .editingDidEndOnExit)
        field.backgroundColor = UIColor(white: 0.16, alpha: 1)
        field.heightAnchor.constraint(equalToConstant: 50).isActive = true
        stack.addArrangedSubview(field)
        let status = self.label("Это код приватки. Код из Telegram или SMS сюда вводить не нужно.", size: 13)
        stack.addArrangedSubview(status)
        let button = UIButton(type: .system)
        button.setTitle("Открыть GhostGram", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor(red: 0.48, green: 0.32, blue: 0.77, alpha: 1)
        button.layer.cornerRadius = 14
        button.heightAnchor.constraint(equalToConstant: 52).isActive = true
        button.addTarget(self, action: #selector(self.submit), for: .touchUpInside)
        stack.addArrangedSubview(button)
        let scroll = UIScrollView(frame: cover.bounds)
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.keyboardDismissMode = .onDrag
        cover.addSubview(scroll); scroll.addSubview(stack)
        self.scrollView = scroll
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 80),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -28),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -40)
        ])
        self.cover = cover; self.field = field; self.statusLabel = status; self.button = button
        host.addSubview(cover)
    }

    @objc private func submit() {
        let token = self.field?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard token.range(of: "^[A-Za-z0-9_-]{32,128}$", options: .regularExpression) != nil else {
            self.statusLabel?.text = "Вставь полный личный код от администратора."
            return
        }
        self.verify(token)
    }

    private func verify(_ token: String) {
        guard !self.checking else { return }
        self.checking = true
        self.nextCheck = self.now + 10
        self.button?.isEnabled = false
        self.statusLabel?.text = "Проверяем личный код…"
        let requestedAccount = self.accountId
        let generation = self.generation
        var request = URLRequest(url: URL(string: "https://sync.grastey.com/v1/me")!)
        request.timeoutInterval = 15
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        self.task = URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            var id: Int64?
            var message = "Не удалось связаться с сервером приватки. Проверь интернет и повтори."
            let code = (response as? HTTPURLResponse)?.statusCode
            if code == 200, let data, data.count <= 4096,
               let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               let raw = value["account"] as? String, raw.range(of: "^[1-9][0-9]{0,15}$", options: .regularExpression) != nil,
               let candidate = Int64(raw), (value["protocol"] as? Int) == 1 {
                if (value["private_access"] as? Bool) == true {
                    if requestedAccount == nil || requestedAccount == candidate { id = candidate }
                    else { message = "Этот код выдан другому Telegram-аккаунту. Нужен код для ID \(requestedAccount!)." }
                } else { message = "Этот код ещё не включён в приватку. Обратись к администратору." }
            } else if code == 401 || code == 403 {
                message = "Код недействителен, истёк или доступ отозван. Обратись к администратору."
            }
            let verified = id
            let failureMessage = message
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == generation, self.accountId == requestedAccount else { return }
                self.checking = false
                self.task = nil
                self.button?.isEnabled = true
                if let verified {
                    self.grantedId = verified; self.grantedToken = token
                    if !GhostGramSyncStorage.saveToken(accountId: verified, token: token) {
                        GhostGramSyncStorage.setSessionToken(accountId: verified, token: token)
                    }
                    if requestedAccount != nil { self.boundId = verified }
                    UserDefaults.standard.set(NSNumber(value: verified), forKey: "ghostgram.private.expectedId")
                    self.leaseUntil = self.now + 60
                    self.nextCheck = self.now + 30
                    if self.active {
                        self.cover?.endEditing(true)
                        self.cover?.removeFromSuperview()
                        self.cover = nil
                    }
                } else {
                    self.leaseUntil = 0
                    if self.active { self.show() }
                    self.statusLabel?.text = failureMessage
                }
            }
        }
        self.task?.resume()
    }
}
