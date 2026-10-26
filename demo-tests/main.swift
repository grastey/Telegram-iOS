import Foundation

let valid: [(String, Int64)] = [
    ("0", 0), ("100", 100_000_000_000), ("0.000000001", 1),
    ("2,5", 2_500_000_000), ("1.123456789", 1_123_456_789),
    ("1000000000", 1_000_000_000_000_000_000)
]
for (text, expected) in valid {
    precondition(DemoWallet.parseTon(text) == expected, "Incorrect TON parsing: \(text)")
}
for text in ["", "-1", "+1", ".5", "1.2.3", "NaN", "1e3", "1.0000000001", "1000000000.1", "999999999999999999999999", "١", " 1"] {
    precondition(DemoWallet.parseTon(text) == nil, "Accepted invalid TON amount: \(text)")
}
for nanos: Int64 in [0, 1, 100_000_000, 1_000_000_001, 1_000_000_000_000_000_000] {
    let wallet = DemoWallet(stars: 0, tonNanograms: nanos)
    precondition(DemoWallet.parseTon(wallet.tonText) == nanos, "TON formatting lost precision")
}
precondition(DemoWallet(stars: -1, tonNanograms: -1).stars == 0)
precondition(DemoWallet(stars: Int64.max, tonNanograms: Int64.max).tonNanograms == 1_000_000_000_000_000_000)
let accountA: Int64 = -9_100_001
let accountB: Int64 = -9_100_002
defer {
    for id in [accountA, accountB] {
        for key in ["stars", "ton"] {
            UserDefaults.standard.removeObject(forKey: "demoWallet.\(id).\(key)")
        }
    }
}
var walletChangeCount = 0
let walletObserver = NotificationCenter.default.addObserver(forName: DemoWallet.didChange, object: nil, queue: nil) { _ in
    walletChangeCount += 1
}
DemoWallet(stars: 42, tonNanograms: 123).save(accountId: accountA)
DemoWallet(stars: 99, tonNanograms: 456).save(accountId: accountB)
NotificationCenter.default.removeObserver(walletObserver)
precondition(walletChangeCount == 2, "Local balance displays were not notified of wallet saves")
precondition(DemoWallet.load(accountId: accountA).stars == 42)
precondition(DemoWallet.load(accountId: accountB).tonNanograms == 456)
precondition(DemoWallet.load(accountId: accountA).stars == 42, "Writing account B overwrote A")
print("Demo wallet: parsing, precision, limits, persistence and account isolation passed.")

// Stars and TON must debit independently, preserve exact nanos and clamp safely.
let spendingWallet = DemoWallet(stars: 1000, tonNanograms: 10_000_000_001)
let afterStars = spendingWallet.spending(stars: 499)
precondition(afterStars.stars == 501 && afterStars.tonNanograms == 10_000_000_001)
let afterTon = afterStars.spending(tonNanograms: 6_770_000_000)
precondition(afterTon.stars == 501 && afterTon.tonNanograms == 3_230_000_001)
precondition(afterTon.spending(stars: Int64.max).stars == 0)
precondition(afterTon.spending(tonNanograms: Int64.max).tonNanograms == 0)
precondition(afterTon.spending(stars: -1, tonNanograms: Int64.min).stars == 501)
precondition(afterTon.spending(stars: -1, tonNanograms: Int64.min).tonNanograms == 3_230_000_001)
let afterRegularGift = spendingWallet.spending(stars: 15).spending(stars: 25)
precondition(afterRegularGift.stars == 960 && afterRegularGift.tonNanograms == 10_000_000_001)
print("Demo spending: Stars, TON, upgrades, exact nanos and overflow limits passed.")
