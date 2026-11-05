import Foundation

func check(_ condition: @autoclosure () -> Bool) {
    precondition(condition())
}
check(FreddyCommand.parse("/freddy")?.caption == "")
check(FreddyCommand.parse(" /FREDDY  Happy Halloween 🎃 ")?.caption == "Happy Halloween 🎃")
check(FreddyCommand.parse("/halloween Привет")?.caption == "Привет")
for ordinary in ["hello", "/freddy123", "/freddy@somebot", "hello /freddy", ""] {
    check(FreddyCommand.parse(ordinary) == nil)
}
check(FreddyCommand.parse("/freddy " + String(repeating: "a", count: 1100))?.caption.count == 1024)
check(FreddyCommand.parse("/ФРЕДИ")?.caption == "")
check(FreddyCommand.parse("/фредди Привет")?.caption == "Привет")
for command in ["/freddy", "/halloween", "/фреди", "/фредди Привет"] {
    check(FreddyCommand.shouldReplaceIncoming(text: command, isIncoming: true, isPersonalChat: true, hasMedia: false, isForwarded: false, authorMatchesChat: true))
}
check(!FreddyCommand.shouldReplaceIncoming(text: "/freddy", isIncoming: false, isPersonalChat: true, hasMedia: false, isForwarded: false, authorMatchesChat: true))
check(!FreddyCommand.shouldReplaceIncoming(text: "/freddy", isIncoming: true, isPersonalChat: false, hasMedia: false, isForwarded: false, authorMatchesChat: true))
check(!FreddyCommand.shouldReplaceIncoming(text: "/freddy", isIncoming: true, isPersonalChat: true, hasMedia: true, isForwarded: false, authorMatchesChat: true))
check(!FreddyCommand.shouldReplaceIncoming(text: "/freddy", isIncoming: true, isPersonalChat: true, hasMedia: false, isForwarded: true, authorMatchesChat: true))
check(!FreddyCommand.shouldReplaceIncoming(text: "/freddy", isIncoming: true, isPersonalChat: true, hasMedia: false, isForwarded: false, authorMatchesChat: false))
check(!FreddyCommand.shouldReplaceIncoming(text: "hello /freddy", isIncoming: true, isPersonalChat: true, hasMedia: false, isForwarded: false, authorMatchesChat: true))
print("Freddy command tests passed")

// Every alias selects its own artwork and fixed price; the entire remaining text is the caption.
check(LocalCommandGift.all.count == 10)
let allIds = LocalCommandGift.all.map { $0.id }
check(Set(allIds).count == allIds.count)
let allResourceIds = LocalCommandGift.all.map { $0.resourceId }
check(Set(allResourceIds).count == allResourceIds.count)
check(Set(allIds).isDisjoint(with: Set(allResourceIds)))
let allAliases = LocalCommandGift.all.flatMap { $0.aliases }
check(Set(allAliases).count == allAliases.count)
for gift in LocalCommandGift.all {
    for alias in gift.aliases {
        check(FreddyCommand.parse(alias)?.gift == gift)
        check(FreddyCommand.parse(" \n" + alias.uppercased() + "\t С днём рождения! 🎁\nОт друга ")?.caption == "С днём рождения! 🎁\nОт друга")
        check(FreddyCommand.parse(alias + "\n  ")?.caption == "")
        check(FreddyCommand.parse(alias + "123") == nil)
        check(FreddyCommand.parse(alias + "@somebot") == nil)
        check(FreddyCommand.shouldReplaceIncoming(text: alias, isIncoming: true, isPersonalChat: true, hasMedia: false, isForwarded: false, authorMatchesChat: true))
        check(!FreddyCommand.shouldReplaceIncoming(text: alias, isIncoming: true, isPersonalChat: false, hasMedia: false, isForwarded: false, authorMatchesChat: true))
        check(!FreddyCommand.shouldReplaceIncoming(text: alias, isIncoming: true, isPersonalChat: true, hasMedia: true, isForwarded: false, authorMatchesChat: true))
        check(!FreddyCommand.shouldReplaceIncoming(text: alias, isIncoming: true, isPersonalChat: true, hasMedia: false, isForwarded: true, authorMatchesChat: true))
        check(!FreddyCommand.shouldReplaceIncoming(text: alias, isIncoming: true, isPersonalChat: true, hasMedia: false, isForwarded: false, authorMatchesChat: false))
    }
    if gift.id != LocalCommandGift.freddy.id {
        check([100, 500, 1000, 2500, 5000].contains(gift.stars))
        check(gift.resourceExtension == "tgs")
        check(gift.mimeType == "application/x-tgsticker")
    }
}
check(FreddyCommand.parse("/тедди Люблю тебя ❤️")?.caption == "Люблю тебя ❤️")
check(FreddyCommand.parse("/тедди")?.gift.resourceName == "ChatGiftTeddy")
check(FreddyCommand.parse("/тедди /звезда это комментарий")?.caption == "/звезда это комментарий")
check(FreddyCommand.parse("/тедди " + String(repeating: "👨‍👩‍👧‍👦", count: 1050))?.caption.count == 1024)
check(FreddyCommand.parse("/unknown") == nil)
print("All 10 local gifts, Cyrillic/English aliases, captions, IDs and incoming eligibility passed")
