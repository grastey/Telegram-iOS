import Foundation
import UIKit

// Simulator-only fixture: no real Telegram account or production key is used.
enum GhostGramSyncStorage {
    static var values: [Int64: String] = [:]
    static func token(accountId: Int64) -> String? { values[accountId] }
    static func saveToken(accountId: Int64, token: String?) -> Bool { values[accountId] = token; return true }
    static func setSessionToken(accountId: Int64, token: String?) { values[accountId] = token }
}

final class AdmissionProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "sync.grastey.com" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let valid = request.value(forHTTPHeaderField: "Authorization") == "Bearer " + String(repeating: "a", count: 64)
        let response = HTTPURLResponse(url: request.url!, statusCode: valid ? 200 : 401, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let body = valid ? "{\"account\":\"8277161585\",\"protocol\":1,\"private_access\":true}" : "{\"error\":\"unauthorized\"}"
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

@main final class AdmissionPreview: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var results: [String: Bool] = [:]
    func children(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap { children($0) } }
    func check(_ name: String, blocked: Bool) {
        guard let window else { return }
        let visible = children(window).contains { $0 is UITextField }
        results[name] = visible == blocked
        let file = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("admission-qa.json")
        try? JSONSerialization.data(withJSONObject: results, options: [.sortedKeys]).write(to: file)
    }
    func enter(_ character: String) {
        guard let window, let field = children(window).compactMap({ $0 as? UITextField }).first,
              let button = children(window).compactMap({ $0 as? UIButton }).first else { return }
        field.text = String(repeating: character, count: 64)
        button.sendActions(for: .touchUpInside)
    }
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        URLProtocol.registerClass(AdmissionProtocol.self)
        UserDefaults.standard.removeObject(forKey: "ghostgram.private.expectedId")
        let window = UIWindow(frame: UIScreen.main.bounds)
        let controller = UIViewController()
        controller.view.backgroundColor = UIColor(white: 0.08, alpha: 1)
        let label = UILabel(frame: CGRect(x: 28, y: 140, width: 310, height: 100))
        label.text = "Telegram sign-in\nAccess granted"; label.numberOfLines = 0; label.textColor = .white
        controller.view.addSubview(label)
        window.rootViewController = controller
        self.window = window
        window.makeKeyAndVisible()
        GhostGramPrivateAccess.shared.attach(to: window)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.check("initial_gate", blocked: true) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.enter("b") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.check("invalid_code_blocked", blocked: true) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.enter("a") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.check("valid_code_opens_login", blocked: false) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { GhostGramPrivateAccess.shared.setAccount(9271733211) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { self.check("wrong_account_blocked", blocked: true) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { GhostGramPrivateAccess.shared.setAccount(8277161585) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { self.check("correct_account_opens", blocked: false) }
        return true
    }
}
