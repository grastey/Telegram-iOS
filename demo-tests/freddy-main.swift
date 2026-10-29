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
print("Freddy command tests passed")
