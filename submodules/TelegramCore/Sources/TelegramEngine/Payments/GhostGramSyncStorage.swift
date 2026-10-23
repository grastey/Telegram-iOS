import Foundation
import Security
import CryptoKit

public enum GhostGramSyncStorage {
    public static let changed = Notification.Name("GhostGramSyncSettingsChanged")
    private static let lock = NSLock()
    private static let service = "dev.grastey.ghostgram.sync"

    public static func token(accountId: Int64) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: String(accountId),
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var value: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &value) == errSecSuccess, let data = value as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func saveToken(accountId: Int64, token: String?) -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: String(accountId)]
        let status: OSStatus
        if let token {
            let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8),
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
            let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if updated == errSecItemNotFound {
                status = SecItemAdd(query.merging(attributes, uniquingKeysWith: { _, new in new }) as CFDictionary, nil)
            } else {
                status = updated
            }
        } else {
            let deleted = SecItemDelete(query as CFDictionary)
            status = deleted == errSecItemNotFound ? errSecSuccess : deleted
        }
        if status == errSecSuccess { NotificationCenter.default.post(name: changed, object: nil) }
        return status == errSecSuccess
    }

    private static func outboxKey(_ accountId: Int64) -> String { return "ghostgram.sync.\(accountId).outbox" }

    public static func enqueue(accountId: Int64, submission: GhostGramGiftSubmission) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        var items = self.readOutbox(accountId)
        guard items.count < 200 else { return false }
        items.append(submission)
        guard let data = try? JSONEncoder().encode(items) else { return false }
        UserDefaults.standard.set(data, forKey: outboxKey(accountId))
        return true
    }

    private static func readOutbox(_ accountId: Int64) -> [GhostGramGiftSubmission] {
        guard let data = UserDefaults.standard.data(forKey: outboxKey(accountId)) else { return [] }
        return (try? JSONDecoder().decode([GhostGramGiftSubmission].self, from: data)) ?? []
    }

    public static func pending(accountId: Int64) -> [GhostGramGiftSubmission] {
        lock.lock()
        defer { lock.unlock() }
        return readOutbox(accountId)
    }

    public static func acknowledge(accountId: Int64, clientId: String) {
        lock.lock()
        defer { lock.unlock() }
        let items = readOutbox(accountId).filter { $0.client_id != clientId }
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: outboxKey(accountId))
        }
    }

    public static func cursor(accountId: Int64) -> Int64 {
        return (UserDefaults.standard.object(forKey: "ghostgram.sync.\(accountId).cursor") as? NSNumber)?.int64Value ?? 0
    }

    public static func saveCursor(accountId: Int64, cursor: Int64) {
        UserDefaults.standard.set(NSNumber(value: cursor), forKey: "ghostgram.sync.\(accountId).cursor")
    }

    public static func messageUniqueId(sender: String, clientId: String) -> Int64 {
        let bytes = SHA256.hash(data: Data(("ghostgram-v1:" + sender + ":" + clientId.lowercased()).utf8))
        let value = bytes.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        return Int64(bitPattern: value)
    }

    /// Consume only when a received card becomes visible. Replayed pages are not new receipts.
    public static func consumeIncomingConfetti(accountId: Int64, messageUniqueId: Int64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let key = "ghostgram.sync.\(accountId).confetti.\(messageUniqueId)"
        guard !UserDefaults.standard.bool(forKey: key) else { return false }
        UserDefaults.standard.set(true, forKey: key)
        return true
    }
}
