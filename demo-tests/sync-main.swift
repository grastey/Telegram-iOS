import Foundation

let regular = GhostGramGiftSubmission(
    clientId: "e5c435df-fae0-4db5-995f-2301131b817d", recipient: "202",
    gift: GhostGramGiftReference(regularId: 5_170_145_012_310_081_615), comment: "Привет 🎁\nДля тебе"
)
let encoder = JSONEncoder()
let data = try encoder.encode(regular)
let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
let giftObject = object["gift"] as! [String: Any]
precondition(giftObject["id"] as? String == "5170145012310081615", "Gift IDs lost integer precision")
precondition(giftObject["slug"] == nil, "Regular references must omit slug")
let decodedRegular = try JSONDecoder().decode(GhostGramGiftSubmission.self, from: data)
precondition(decodedRegular == regular)
let unique = GhostGramGiftSubmission(recipient: "202", gift: GhostGramGiftReference(collectibleSlug: "LibertyFigure-21114"), comment: "")
let uniqueData = try encoder.encode(unique)
let decodedUnique = try JSONDecoder().decode(GhostGramGiftSubmission.self, from: uniqueData)
precondition(decodedUnique == unique)
let wire = """
{"events":[{"seq":1,"event_id":"a","client_id":"e5c435df-fae0-4db5-995f-2301131b817d","sender":"101","recipient":"202","gift":{"kind":"regular","id":"5170145012310081615"},"comment":"Привет 🎁\\nДля тебе","created":1792700000,"synthetic":true}],"cursor":1,"has_more":false}
"""
let page = try JSONDecoder().decode(GhostGramEventPage.self, from: Data(wire.utf8))
precondition(page.events[0].comment == regular.comment)
precondition(page.events[0].belongs(to: "101"))
precondition(page.events[0].belongs(to: "202"))
precondition(!page.events[0].belongs(to: "303"))
precondition(page.cursor == 1 && !page.has_more)
print("GhostGram wire protocol: IDs, comments, gift references and account isolation passed")
