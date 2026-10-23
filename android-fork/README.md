# GhostGram Android private beta sources

Base: official [DrKLO/Telegram](https://github.com/DrKLO/Telegram) at the exact
commit in `upstream-commit.txt`. `ghostgram.patch` contains the changed
Java files, including the new relay client. The upstream GPL license applies.

The client uses `https://sync.grastey.com` and protocol v1. It needs the relay
identity endpoint `/v1/me` before enrollment. Session tokens are account-scoped,
encrypted with an Android Keystore AES-GCM key, and never embedded in an APK.
Configure via Settings -> three dots -> Synchronization GhostGram. The dialog
also shows the numeric Telegram user ID. Only server-enrolled account pairs
can exchange synthetic gifts. No Telegram login credentials go to the relay.

Regular gifts, owned collectible transfers and market purchases are intercepted before payment calls and
inserted as local service cards. The sender/recipient can receive the same event
on another enrolled client. The foreground poll interval is five seconds;
background/push delivery is not implemented. Read-only native catalog calls
resolve regular IDs and collectible slugs. Gift comments use plain Unicode text
in relay v1. The local queue has a 200-item cap, with persistent idempotency UUIDs.

Messages have `send_state=0` and never enter Telegram's outgoing queue. Imports
check `randoms_v2` and insert through the existing messages storage queue; an
event is acknowledged locally only after its message/random ID exists. Server
pages are not acknowledged until all events on that page have been imported.

`prepare.py` injects the existing Telegram API credentials without printing them,
changes the fork package, disables official updater/billing/passkeys and configures
an arm64 unsigned app. The code-validation workflow compiles Java without producing
an installable APK. No private signing material is uploaded. Signing and actual
device tests remain pending for the updated wallet/catalog implementation.

The local wallet starts at 100,000 Stars and 100 TON per account, with an editor
in Settings -> three dots -> Balance. It uses exact decimal parsing, the same
limits as iOS, clamped spending, and a persistent per-event cost marker to avoid
double charging on relay retries. Gift and market headers observe the same
wallet change notifications. It never overrides the real payment balance.

All routes to the market for gifts with resale offers; Collectibles shows the
ordinary catalog. There is no separate Catalog tab. Regular and collectible
cards retain comments; gifts also work locally without a configured relay key.
Local resale quotes avoid payment-form requests and balance-top-up prompts.
