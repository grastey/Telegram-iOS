import gzip
import hashlib
import json
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / 'demo-tests/chat-gifts-manifest.json').read_text(encoding='utf-8'))
registry = (root / 'submodules/TelegramCore/Sources/TelegramEngine/Payments/FreddyCommand.swift').read_text(encoding='utf-8')
assert len(manifest) == 9
assert len({entry['resource'] for entry in manifest}) == 9
for entry in manifest:
    path = root / 'submodules/TelegramUI/Resources' / (entry['resource'] + '.tgs')
    data = path.read_bytes()
    assert hashlib.sha256(data).hexdigest() == entry['sha256'], path
    animation = json.loads(gzip.decompress(data))
    assert (animation['w'], animation['h'], animation['fr']) == (512, 512, 60), path
    assert 0 < animation['op'] - animation['ip'] <= 180, path
    assert animation.get('layers'), path
    assert not animation.get('assets') or all(not a.get('p') for a in animation['assets']), path
    assert f'resourceName: "{entry["resource"]}"' in registry
    assert f'"{entry["command"]}"' in registry
    assert entry['stars'] in (100, 500, 1000, 2500, 5000)

# Mixed incoming commands must have a cache keyed by gift identity, not a shared Freddy cache.
history = (root / 'submodules/TelegramUI/Sources/ChatHistoryEntriesForView.swift').read_text(encoding='utf-8')
assert 'currentState.commandGifts[command.gift.id]' in history
assert 'currentState.freddyGift' not in history
gift = (root / 'submodules/TelegramCore/Sources/TelegramEngine/Payments/FreddyGift.swift').read_text(encoding='utf-8')
assert 'value.id == command.gift.id' in gift
assert 'command.gift.stars' in gift
assert 'fileId: definition.resourceId' in gift
bubble = (root / 'submodules/TelegramUI/Components/Chat/ChatMessageGiftBubbleContentNode/Sources/ChatMessageGiftBubbleContentNode.swift').read_text(encoding='utf-8')
assert 'text = giftText' in bubble
assert 'Int32(clamping: gift.convertStars)' in bubble
assert 'item.controllerInteraction.animateDiceSuccess(false, true)' in bubble
print('PASS: 9 original TGS payloads, resources, per-gift caches, prices, captions, confetti hooks')
