import Foundation
import UIKit
import MetalEngine
import CompanionRenderer

public final class ChatCompanionView: UIView {
    private final class LinkTarget: NSObject {
        weak var view: ChatCompanionView?

        @objc func tick(_ link: CADisplayLink) {
            self.view?.tick(link)
        }
    }

    private let character = CompanionLayer()
    private var displayLink: CADisplayLink?
    private var lastFrame: CFTimeInterval = 0

    public init?(previewFrame: CGRect) {
        let bundle = Bundle(for: CompanionRenderer.self)
        guard let path = bundle.path(forResource: "CompanionResources", ofType: "bundle"),
              let directory = Bundle(path: path)?.resourcePath,
              let renderer = try? CompanionRenderer(device: MetalEngine.shared.device, resourceDirectory: directory) else {
            return nil
        }
        do {
            try renderer.loadDefault()
        } catch {
            return nil
        }
        super.init(frame: previewFrame)
        self.character.renderer = renderer
        self.layer.addSublayer(self.character)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.displayLink?.invalidate()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        self.character.frame = self.bounds
        self.character.setNeedsUpdate()
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        self.displayLink?.invalidate()
        self.displayLink = nil
        self.lastFrame = 0
        self.character.active = self.window != nil
        guard self.window != nil else {
            self.character.releaseSurface()
            return
        }
        let target = LinkTarget()
        target.view = self
        let link = CADisplayLink(target: target, selector: #selector(LinkTarget.tick(_:)))
        link.preferredFramesPerSecond = 30
        link.add(to: .main, forMode: .common)
        self.displayLink = link
    }

    private func tick(_ link: CADisplayLink) {
        guard UIApplication.shared.applicationState == .active else {
            self.lastFrame = 0
            return
        }
        self.character.deltaTime = self.lastFrame == 0 ? 0 : Float(min(0.1, link.timestamp - self.lastFrame))
        self.lastFrame = link.timestamp
        self.character.setNeedsUpdate()
    }
}
