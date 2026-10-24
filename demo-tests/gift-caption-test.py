"""Exercise production gift caption normalization and persistence branches with Swift."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
ui = (root / 'submodules/TelegramUI/Components/Chat/ChatMessageGiftBubbleContentNode/Sources/ChatMessageGiftBubbleContentNode.swift').read_text()
helper = ui.split('private func localGiftCaption', 1)[1].split('private func attributedServiceMessageString', 1)[0]
gift = (root / 'submodules/TelegramCore/Sources/TelegramEngine/Payments/DemoGift.swift').read_text()
normalize = gift.split('let caption: String?', 1)[1].split('let actionType:', 1)[0]
actions = (root / 'submodules/TelegramCore/Sources/SyncCore/SyncCore_TelegramMediaAction.swift').read_text()
encode = actions.split('encoder.encodeInt32(44, forKey:', 1)[1]
encode = encode[encode.index('if let text, let entities {'):encode.index('encoder.encodeBool(nameHidden,')]
harness = '''
import Foundation
struct MessageTextEntity { let value: Int }
final class Recorder {
    var text: String?
    var entities: [MessageTextEntity]?
    func encodeString(_ value: String, forKey: String) { text = value }
    func encodeObjectArray(_ value: [MessageTextEntity], forKey: String) { entities = value }
    func encodeNil(forKey: String) {}
}
func persist(_ text: String, entities: [MessageTextEntity]?) -> Recorder {
    let caption: String? NORMALIZE
    let text = caption
    let entities = captionEntities
    let encoder = Recorder()
    ENCODE
    return encoder
}
HELPER
let comment = "Привіт ❤️\\nПодарунок 🎁"
let received = persist(comment, entities: nil)
precondition(received.text == comment && received.entities?.isEmpty == true)
let formatted = persist(comment, entities: [MessageTextEntity(value: 7)])
precondition(formatted.text == comment && formatted.entities?.first?.value == 7)
precondition(persist("", entities: nil).text == nil)
precondition(localGiftCaption(nil, localMessageText: comment, isDemo: false) == comment)
precondition(localGiftCaption("original", localMessageText: comment, isDemo: false) == "original")
precondition(localGiftCaption(nil, localMessageText: "ДЕМО • Подарок не отправлен", isDemo: true) == nil)
precondition(localGiftCaption("ДЕМО • Только на этом устройстве\\n" + comment, isDemo: true) == comment)
print("Gift caption persistence and legacy rendering: passed")
'''.replace('NORMALIZE', normalize).replace('ENCODE', encode).replace('HELPER', 'func localGiftCaption' + helper)
with tempfile.TemporaryDirectory() as directory:
    source = Path(directory) / 'main.swift'
    source.write_text(harness)
    binary = Path(directory) / 'tests'
    subprocess.run(['swiftc', str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
