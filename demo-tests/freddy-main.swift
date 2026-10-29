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
