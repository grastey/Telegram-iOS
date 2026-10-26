import Foundation

/// Local presentation data for this demo fork. Never use these values in payment requests.
public struct DemoWallet {
    public static let isEnabled = true
    public static let didChange = Notification.Name("localWalletDidChange")
    public let stars: Int64
    public let tonNanograms: Int64

    public init(stars: Int64, tonNanograms: Int64) {
        self.stars = max(0, min(1_000_000_000_000, stars))
        self.tonNanograms = max(0, min(1_000_000_000_000_000_000, tonNanograms))
    }

    public static func load(accountId: Int64) -> DemoWallet {
        let defaults = UserDefaults.standard
        let prefix = "demoWallet.\(accountId)."
        return DemoWallet(
            stars: (defaults.object(forKey: prefix + "stars") as? NSNumber)?.int64Value ?? 100_000,
            tonNanograms: (defaults.object(forKey: prefix + "ton") as? NSNumber)?.int64Value ?? 100_000_000_000
        )
    }

    /// Clamp simulated spending without borrowing across currencies or overflowing.
    public func spending(stars: Int64 = 0, tonNanograms: Int64 = 0) -> DemoWallet {
        return DemoWallet(
            stars: self.stars - min(self.stars, max(0, stars)),
            tonNanograms: self.tonNanograms - min(self.tonNanograms, max(0, tonNanograms))
        )
    }

    public func save(accountId: Int64) {
        let prefix = "demoWallet.\(accountId)."
        UserDefaults.standard.set(NSNumber(value: self.stars), forKey: prefix + "stars")
        UserDefaults.standard.set(NSNumber(value: self.tonNanograms), forKey: prefix + "ton")
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    /// Decimal parsing without floating point rounding or integer overflow.
    public static func parseTon(_ text: String) -> Int64? {
        let parts = text.replacingOccurrences(of: ",", with: ".").split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 2, let whole = Int64(parts[0]), whole >= 0, whole <= 1_000_000_000,
              parts[0].allSatisfy({ $0.isASCII && $0.isNumber }) else {
            return nil
        }
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        guard fraction.count <= 9, fraction.allSatisfy({ $0.isASCII && $0.isNumber }),
              let nanos = Int64(fraction + String(repeating: "0", count: 9 - fraction.count)),
              whole < 1_000_000_000 || nanos == 0 else {
            return nil
        }
        return whole * 1_000_000_000 + nanos
    }

    public var tonText: String {
        let whole = self.tonNanograms / 1_000_000_000
        let fraction = String(format: "%09lld", self.tonNanograms % 1_000_000_000)
        let trimmed = String(fraction.reversed().drop(while: { $0 == "0" }).reversed())
        return trimmed.isEmpty ? String(whole) : "\(whole).\(trimmed)"
    }
}
