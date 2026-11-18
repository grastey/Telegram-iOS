import Foundation

public enum GhostGramStreakSettings {
    public static func isEnabled(accountId: Int64) -> Bool {
        return UserDefaults.standard.bool(forKey: "GhostGram.streak.enabled.\(accountId)")
    }

    public static func setEnabled(_ value: Bool, accountId: Int64) {
        UserDefaults.standard.set(value, forKey: "GhostGram.streak.enabled.\(accountId)")
    }
}
