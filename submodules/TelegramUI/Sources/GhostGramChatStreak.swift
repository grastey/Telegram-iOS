import Foundation
import UIKit
import Display
import Postbox
import TelegramCore
import SwiftSignalKit
import DebugCompanionScreen

extension ChatControllerImpl {
    func startGhostGramStreak() {
        guard self.ghostGramStreak == nil,
              case let .peer(peerId) = self.chatLocation,
              peerId.namespace == Namespaces.Peer.CloudUser,
              peerId != self.context.account.peerId,
              GhostGramStreakSettings.isEnabled(accountId: self.context.account.peerId.toInt64()) else {
            return
        }
        let streak = GhostGramChatStreak(controller: self, peerId: peerId)
        self.ghostGramStreak = streak
        streak.start()
    }
}

final class GhostGramChatStreak: NSObject {
    private enum Palette: String, CaseIterable, Codable {
        case violet, orange, ice, red, mint

        var name: String {
            switch self {
            case .violet: return "Фиолетовый"
            case .orange: return "Оранжевый"
            case .ice: return "Голубой"
            case .red: return "Красный"
            case .mint: return "Мятный"
            }
        }

        var color: UIColor {
            switch self {
            case .violet: return UIColor(red: 0.60, green: 0.30, blue: 1, alpha: 1)
            case .orange: return UIColor(red: 1, green: 0.52, blue: 0.14, alpha: 1)
            case .ice: return UIColor(red: 0.23, green: 0.67, blue: 1, alpha: 1)
            case .red: return UIColor(red: 1, green: 0.29, blue: 0.38, alpha: 1)
            case .mint: return UIColor(red: 0.13, green: 0.74, blue: 0.54, alpha: 1)
            }
        }
    }

    private struct Configuration: Codable {
        var count: Int
        var palette: Palette
        var showsPet: Bool
    }

    private weak var controller: ChatControllerImpl?
    private let peerId: PeerId
    private let storageKey: String
    private let history = MetaDisposable()
    private var configuration: Configuration?
    private var pet: UIView?
    private var overlay: UIView?
    private var calendarDay: Date?
    private var sawIncoming = false
    private var sawOutgoing = false
    private var isComplete = false
    private var top: CGFloat?
    private let badge = UILabel()

    init(controller: ChatControllerImpl, peerId: PeerId) {
        self.controller = controller
        self.peerId = peerId
        self.storageKey = "GhostGram.streak.\(controller.context.account.peerId.toInt64()).\(peerId.toInt64())"
        if let data = UserDefaults.standard.data(forKey: self.storageKey) {
            self.configuration = try? JSONDecoder().decode(Configuration.self, from: data)
        }
        super.init()
        self.badge.textAlignment = .center
        self.badge.font = .monospacedDigitSystemFont(ofSize: 12, weight: .bold)
        self.badge.adjustsFontSizeToFitWidth = true
        self.badge.minimumScaleFactor = 0.60
        self.badge.layer.cornerRadius = 9
        self.badge.clipsToBounds = true
        self.badge.isAccessibilityElement = true
    }

    func start() {
        NotificationCenter.default.addObserver(self, selector: #selector(self.refreshDay), name: .NSCalendarDayChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.refreshDay), name: UIApplication.didBecomeActiveNotification, object: nil)
        self.refreshDay()
    }

    func stop() {
        NotificationCenter.default.removeObserver(self)
        self.history.dispose()
        self.overlay?.removeFromSuperview()
        self.pet?.removeFromSuperview()
        self.controller?.chatTitleView?.streakBadge = nil
    }

    deinit {
        self.history.dispose()
    }

    @objc private func refreshDay() {
        guard let controller = self.controller else { return }
        self.refreshBadge()
        guard self.configuration != nil else { return }
        let signal = controller.context.account.viewTracker.aroundMessageHistoryViewForLocation(
            .peer(peerId: self.peerId, threadId: nil), index: .upperBound, anchorIndex: .upperBound, count: 120
        )
        self.history.set((signal |> deliverOnMainQueue).start(next: { [weak self] view, _, _ in
            guard !view.isLoading else { return }
            self?.update(entries: view.entries)
        }))
    }

    private func update(entries: [MessageHistoryEntry]) {
        guard let controller = self.controller else { return }
        let day = Calendar.current.startOfDay(for: Date())
        var incoming = self.calendarDay == day && self.sawIncoming
        var outgoing = self.calendarDay == day && self.sawOutgoing
        for entry in entries.reversed() {
            let message = entry.message
            if Date(timeIntervalSince1970: TimeInterval(message.timestamp)) < day { break }
            guard message.id.namespace == Namespaces.Message.Cloud,
                  message.flags.intersection([.Unsent, .Sending, .Failed]).isEmpty,
                  !message.media.contains(where: { $0 is TelegramMediaAction }) else { continue }
            if message.effectivelyIncoming(controller.context.account.peerId) {
                incoming = true
            } else {
                outgoing = true
            }
            if incoming && outgoing { break }
        }
        let completionKey = self.storageKey + ".completed"
        let alreadyCompleted = UserDefaults.standard.object(forKey: completionKey) as? Date == day
        let shouldAnimate = !alreadyCompleted && self.calendarDay != nil && incoming && outgoing
        self.calendarDay = day
        self.sawIncoming = incoming
        self.sawOutgoing = outgoing
        self.isComplete = alreadyCompleted || (incoming && outgoing)
        if self.isComplete && !alreadyCompleted {
            UserDefaults.standard.set(day, forKey: completionKey)
        }
        if shouldAnimate {
            self.play()
        }
        self.refreshBadge()
    }

    private func refreshBadge() {
        guard let controller = self.controller else { return }
        guard let configuration = self.configuration else {
            self.isComplete = false
            self.calendarDay = nil
            self.sawIncoming = false
            self.sawOutgoing = false
            controller.chatTitleView?.streakBadge = nil
            self.pet?.removeFromSuperview()
            self.pet = nil
            return
        }
        let today = Calendar.current.startOfDay(for: Date())
        let active = self.isComplete && self.calendarDay == today && self.overlay == nil
        let color = active ? configuration.palette.color : UIColor.secondaryLabel
        let font = self.badge.font ?? .systemFont(ofSize: 12)
        let attachment = NSTextAttachment()
        attachment.image = UIImage(systemName: "flame.fill")?.withTintColor(color, renderingMode: .alwaysOriginal)
        attachment.bounds = CGRect(x: 0, y: -2, width: 10, height: 12)
        let text = NSMutableAttributedString(attachment: attachment)
        text.append(NSAttributedString(string: " \(configuration.count)", attributes: [.font: font, .foregroundColor: color]))
        self.badge.attributedText = text
        self.badge.accessibilityLabel = "Огонёк, \(configuration.count) дней"
        self.badge.backgroundColor = color.withAlphaComponent(0.15)
        if controller.chatTitleView?.streakBadge !== self.badge {
            controller.chatTitleView?.streakBadge = self.badge
        }
        if configuration.showsPet && self.pet == nil, let pet = ChatCompanionView(previewFrame: .zero) {
            pet.isAccessibilityElement = true
            pet.accessibilityLabel = "Питомец"
            pet.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.openPet)))
            controller.view.addSubview(pet)
            self.pet = pet
        } else if !configuration.showsPet {
            self.pet?.removeFromSuperview()
            self.pet = nil
        }
        self.layout(top: self.top)
    }

    func layout(top: CGFloat?) {
        if let top {
            self.top = top
        }
        guard let controller = self.controller else { return }
        let top = self.top ?? (controller.chatTitleView.map { $0.convert($0.bounds, to: controller.view).maxY } ?? controller.view.safeAreaInsets.top)
        self.pet?.frame = CGRect(x: controller.view.bounds.width - controller.view.safeAreaInsets.right - 82, y: top + 14, width: 74, height: 84)
    }

    @objc private func openPet() {
        guard let controller = self.controller else { return }
        let screen = DebugCompanionScreen(context: controller.context, standalone: false)
        (controller.navigationController as? NavigationController)?.pushViewController(screen)
    }

    func showMenu() {
        let alert = UIAlertController(title: "Огонёк в чате", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Настроить", style: .default) { [weak self] _ in self?.editCount() })
        if let configuration = self.configuration {
            alert.addAction(UIAlertAction(title: "Повторить анимацию", style: .default) { [weak self] _ in self?.play() })
            let petAction = configuration.showsPet ? "Скрыть питомца" : "Показать питомца"
            alert.addAction(UIAlertAction(title: petAction, style: .default) { [weak self] _ in
                var updated = configuration
                updated.showsPet.toggle()
                self?.save(updated)
            })
            alert.addAction(UIAlertAction(title: "Убрать огонёк", style: .destructive) { [weak self] _ in self?.save(nil) })
        }
        alert.addAction(UIAlertAction(title: "Поиск в чате", style: .default) { [weak self] _ in
            self?.controller?.interfaceInteraction?.beginMessageSearch(.everything, "")
        })
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        self.controller?.present(alert, animated: true)
    }

    private func editCount() {
        let alert = UIAlertController(title: "Сколько дней?", message: "От 1 до 999 999", preferredStyle: .alert)
        alert.addTextField { field in
            field.keyboardType = .numberPad
            field.text = String(self.configuration?.count ?? 1)
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Выбрать цвет", style: .default) { [weak self, weak alert] _ in
            guard let value = Int(alert?.textFields?.first?.text ?? ""), (1 ... 999_999).contains(value) else {
                self?.editCount()
                return
            }
            self?.chooseColor(count: value)
        })
        self.controller?.present(alert, animated: true)
    }

    private func chooseColor(count: Int) {
        let alert = UIAlertController(title: "Цвет огонька", message: nil, preferredStyle: .alert)
        for palette in Palette.allCases {
            alert.addAction(UIAlertAction(title: palette.name, style: .default) { [weak self] _ in
                guard let self else { return }
                self.save(Configuration(count: count, palette: palette, showsPet: self.configuration?.showsPet ?? true))
            })
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        self.controller?.present(alert, animated: true)
    }

    private func save(_ configuration: Configuration?) {
        self.configuration = configuration
        if let configuration, let data = try? JSONEncoder().encode(configuration) {
            UserDefaults.standard.set(data, forKey: self.storageKey)
        } else {
            UserDefaults.standard.removeObject(forKey: self.storageKey)
            UserDefaults.standard.removeObject(forKey: self.storageKey + ".completed")
            self.history.set(nil)
        }
        self.refreshDay()
    }

    private func play() {
        guard let controller = self.controller, let configuration = self.configuration,
              let window = controller.view.window, self.badge.window === window, self.overlay == nil else { return }
        let color = configuration.palette.color
        let reducedMotion = UIAccessibility.isReduceMotionEnabled
        let overlay = UIView(frame: window.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.isUserInteractionEnabled = false
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0)
        let center = CGPoint(x: overlay.bounds.midX, y: overlay.bounds.midY - 24)
        let rays = CAReplicatorLayer()
        rays.frame = CGRect(x: center.x - 200, y: center.y - 200, width: 400, height: 400)
        rays.instanceCount = 16
        rays.instanceTransform = CATransform3DMakeRotation(.pi / 8, 0, 0, 1)
        let ray = CAShapeLayer()
        let triangle = UIBezierPath()
        triangle.move(to: CGPoint(x: 200, y: 200))
        triangle.addLine(to: CGPoint(x: 171, y: 0))
        triangle.addLine(to: CGPoint(x: 229, y: 0))
        triangle.close()
        ray.path = triangle.cgPath
        ray.fillColor = color.withAlphaComponent(0.26).cgColor
        rays.addSublayer(ray)
        rays.opacity = 0
        overlay.layer.addSublayer(rays)

        let emblem = UIView(frame: CGRect(x: 0, y: 0, width: 154, height: 164))
        emblem.center = center
        emblem.transform = reducedMotion ? .identity : CGAffineTransform(scaleX: 0.15, y: 0.15)
        emblem.alpha = 0
        overlay.addSubview(emblem)
        let flame = UIImageView(image: UIImage(systemName: "flame.fill"))
        flame.frame = CGRect(x: 15, y: 0, width: 124, height: 136)
        flame.contentMode = .scaleAspectFit
        flame.tintColor = color
        flame.layer.shadowColor = color.cgColor
        flame.layer.shadowOpacity = 0.9
        flame.layer.shadowRadius = 24
        flame.layer.shadowOffset = .zero
        emblem.addSubview(flame)

        let count = UILabel(frame: CGRect(x: 2, y: 113, width: 150, height: 43))
        count.text = String(configuration.count)
        count.font = .monospacedDigitSystemFont(ofSize: 32, weight: .heavy)
        count.textAlignment = .center
        count.textColor = .white
        count.adjustsFontSizeToFitWidth = true
        count.minimumScaleFactor = 0.6
        count.backgroundColor = color
        count.layer.cornerRadius = 16
        count.layer.borderWidth = 2
        count.layer.borderColor = UIColor.white.withAlphaComponent(0.8).cgColor
        count.clipsToBounds = true
        emblem.addSubview(count)

        let confetti = CAEmitterLayer()
        if !reducedMotion {
            confetti.emitterPosition = center
            confetti.emitterShape = .point
            confetti.birthRate = 0
            confetti.emitterCells = [color, .white, UIColor(red: 1, green: 0.78, blue: 0.30, alpha: 1)].map { tint in
                let cell = CAEmitterCell()
                let size = CGSize(width: 5, height: 8)
                cell.contents = UIGraphicsImageRenderer(size: size).image { context in
                    tint.setFill()
                    context.fill(CGRect(origin: .zero, size: size))
                }.cgImage
                cell.birthRate = 75
                cell.lifetime = 1.15
                cell.velocity = 180
                cell.velocityRange = 125
                cell.emissionRange = .pi * 2
                cell.yAcceleration = 145
                cell.spinRange = 7
                cell.alphaSpeed = -0.7
                return cell
            }
            overlay.layer.addSublayer(confetti)
        }
        window.addSubview(overlay)
        self.overlay = overlay
        if !reducedMotion {
            let origin = self.badge.convert(CGPoint(x: self.badge.bounds.midX, y: self.badge.bounds.midY), to: overlay)
            let arrival = CAKeyframeAnimation(keyPath: "position")
            let path = UIBezierPath()
            path.move(to: origin)
            path.addQuadCurve(to: center, controlPoint: CGPoint(x: center.x + 96, y: center.y - 72))
            arrival.path = path.cgPath
            arrival.duration = 0.36
            arrival.timingFunction = CAMediaTimingFunction(name: .easeOut)
            emblem.layer.add(arrival, forKey: "streakArrival")
        }
        UIView.animate(withDuration: reducedMotion ? 0.18 : 0.36, delay: 0, usingSpringWithDamping: 0.70, initialSpringVelocity: 0, options: [.beginFromCurrentState]) {
            overlay.backgroundColor = UIColor.black.withAlphaComponent(0.60)
            emblem.alpha = 1
            emblem.transform = .identity
            rays.opacity = reducedMotion ? 0.4 : 1
        } completion: { [weak self, weak overlay] _ in
            guard let self, let overlay, self.overlay === overlay else { return }
            if !reducedMotion {
                confetti.birthRate = 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { confetti.birthRate = 0 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + (reducedMotion ? 0.48 : 0.85)) { [weak self, weak overlay] in
                guard let self, let overlay, self.overlay === overlay else { return }
                let target = self.badge.convert(CGPoint(x: self.badge.bounds.midX, y: self.badge.bounds.midY), to: overlay)
                let flight = CAKeyframeAnimation(keyPath: "position")
                let path = UIBezierPath()
                path.move(to: emblem.center)
                path.addQuadCurve(to: target, controlPoint: CGPoint(x: max(center.x, target.x) + 78, y: (center.y + target.y) * 0.5))
                flight.path = path.cgPath
                flight.duration = 0.44
                flight.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                if !reducedMotion {
                    UIView.performWithoutAnimation { emblem.center = target }
                    emblem.layer.add(flight, forKey: "streakFlight")
                }
                UIView.animate(withDuration: reducedMotion ? 0.18 : 0.44) {
                    overlay.backgroundColor = .clear
                    if reducedMotion {
                        emblem.alpha = 0
                    } else {
                        rays.opacity = 0
                        emblem.transform = CGAffineTransform(scaleX: 0.12, y: 0.12)
                    }
                } completion: { [weak self, weak overlay] _ in
                    overlay?.removeFromSuperview()
                    guard let self, self.overlay === overlay else { return }
                    self.overlay = nil
                    self.refreshBadge()
                    if !reducedMotion {
                        self.badge.transform = CGAffineTransform(scaleX: 1.22, y: 1.22)
                        UIView.animate(withDuration: 0.28, delay: 0, usingSpringWithDamping: 0.64, initialSpringVelocity: 0, options: []) {
                            self.badge.transform = .identity
                        }
                    }
                }
            }
        }
    }
}
