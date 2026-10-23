import Foundation
import SwiftSignalKit
import Postbox

/// Account-owned foreground relay. Its lifetime must not exceed the account context.
public final class GhostGramSyncManager {
    public static let baseURL = "https://sync.grastey.com"
    private let account: Account
    private var timer: Foundation.Timer?
    private var foreground: Disposable?
    private let resolver = MetaDisposable()
    private let importer = MetaDisposable()
    private let catalogUpdate = MetaDisposable()
    private var observer: NSObjectProtocol?
    private var task: URLSessionDataTask?
    private var active = false
    private var busy = false
    private var generation = 0
    private var verifiedToken: String?

    public init(account: Account, inForeground: Signal<Bool, NoError>) {
        self.account = account
        self.foreground = (inForeground |> deliverOnMainQueue).start(next: { [weak self] value in
            self?.active = value
            self?.tick()
        })
        self.observer = NotificationCenter.default.addObserver(forName: GhostGramSyncStorage.changed, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.generation += 1
            self.task?.cancel()
            self.resolver.set(nil)
            self.importer.set(nil)
            self.busy = false
            self.verifiedToken = nil
            self.tick()
        }
        self.timer = Foundation.Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in self?.tick() }
    }

    deinit {
        self.timer?.invalidate()
        self.foreground?.dispose()
        self.task?.cancel()
        self.resolver.dispose()
        self.importer.dispose()
        self.catalogUpdate.dispose()
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    public static func verify(token: String, accountId: Int64, completion: @escaping (Bool) -> Void) {
        var request = URLRequest(url: URL(string: baseURL + "/v1/me")!)
        request.timeoutInterval = 15
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let identity = data.flatMap { try? JSONDecoder().decode(GhostGramRelayIdentity.self, from: $0) }
            let valid = (response as? HTTPURLResponse)?.statusCode == 200 && identity?.account == String(accountId) && identity?.protocol == 1
            DispatchQueue.main.async { completion(valid) }
        }.resume()
    }

    private func request(_ path: String, token: String, body: Data? = nil, completion: @escaping (Int, Data?) -> Void) {
        var request = URLRequest(url: URL(string: Self.baseURL + path)!)
        request.timeoutInterval = 20
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        if let body {
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let generation = self.generation
        self.task = URLSession.shared.dataTask(with: request) { [weak self] data, response, _ in
            DispatchQueue.main.async {
                guard let self, self.generation == generation else { return }
                completion((response as? HTTPURLResponse)?.statusCode ?? 0, data)
            }
        }
        self.task?.resume()
    }

    private func tick() {
        let id = self.account.peerId.toInt64()
        guard self.active, !self.busy, let token = GhostGramSyncStorage.token(accountId: id) else { return }
        self.busy = true
        if self.verifiedToken != token {
            self.request("/v1/me", token: token) { [weak self] status, data in
                guard let self else { return }
                defer { self.busy = false }
                guard status == 200, let data, let identity = try? JSONDecoder().decode(GhostGramRelayIdentity.self, from: data),
                    identity.account == String(id), identity.protocol == 1 else { return }
                self.verifiedToken = token
            }
            return
        }
        if let next = GhostGramSyncStorage.pending(accountId: id).first, let body = try? JSONEncoder().encode(next) {
            self.request("/v1/gifts", token: token, body: body) { [weak self] status, data in
                guard let self else { return }
                self.busy = false
                if status == 401 { self.verifiedToken = nil }
                if (status == 200 || status == 201), let data, let event = try? JSONDecoder().decode(GhostGramGiftEvent.self, from: data),
                    event.synthetic, event.sender == String(id), event.client_id == next.client_id {
                    GhostGramSyncStorage.acknowledge(accountId: id, clientId: next.client_id)
                }
                self.poll(token: token)
            }
        } else {
            self.busy = false
            self.poll(token: token)
        }
    }

    private func poll(token: String) {
        guard self.active, !self.busy else { return }
        self.busy = true
        let id = self.account.peerId.toInt64()
        let after = GhostGramSyncStorage.cursor(accountId: id)
        self.request("/v1/events?after=\(after)", token: token) { [weak self] status, data in
            guard let self else { return }
            guard status == 200, let data, data.count <= 1_048_576,
                let page = try? JSONDecoder().decode(GhostGramEventPage.self, from: data), page.events.count <= 100,
                page.cursor == (page.events.last?.seq ?? after), page.cursor >= after else {
                self.busy = false
                if status == 401 { self.verifiedToken = nil }
                return
            }
            self.importEvents(page.events, index: 0, previousSequence: after) { [weak self] success in
                guard let self else { return }
                self.busy = false
                if success {
                    GhostGramSyncStorage.saveCursor(accountId: id, cursor: page.cursor)
                    if page.has_more { self.poll(token: token) }
                }
            }
        }
    }

    private func importEvents(_ events: [GhostGramGiftEvent], index: Int, previousSequence: Int64, completion: @escaping (Bool) -> Void) {
        guard index < events.count else { completion(true); return }
        let event = events[index]
        let id = self.account.peerId.toInt64()
        guard event.belongs(to: String(id)), event.seq > previousSequence,
            let sender = Int64(event.sender), let recipient = Int64(event.recipient),
            event.comment.count <= 1024, UUID(uuidString: event.client_id) != nil else { completion(false); return }
        let gift: Signal<StarGift?, NoError>
        if event.gift.kind == "collectible", let slug = event.gift.slug {
            gift = _internal_getUniqueStarGift(account: self.account, slug: slug)
            |> map { value -> StarGift? in .unique(value) }
            |> `catch` { _ -> Signal<StarGift?, NoError> in .single(nil) }
        } else if event.gift.kind == "regular", let giftId = event.gift.id.flatMap(Int64.init) {
            gift = _internal_cachedStarGifts(postbox: self.account.postbox) |> take(1) |> map { list -> StarGift? in
                return list?.items.first(where: { value in if case let .generic(item) = value { return item.id == giftId }; return false })
            }
        } else { completion(false); return }
        self.resolver.set((gift |> deliverOnMainQueue).start(next: { [weak self] value in
            guard let self else { return }
            guard let value else {
                if event.gift.kind == "regular" {
                    self.catalogUpdate.set(_internal_keepCachedStarGiftsUpdated(postbox: self.account.postbox, network: self.account.network, accountPeerId: self.account.peerId).start())
                }
                completion(false)
                return
            }
            let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(sender == id ? recipient : sender))
            let authorId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(sender))
            let uniqueId = GhostGramSyncStorage.messageUniqueId(sender: event.sender, clientId: event.client_id)
            self.importer.set((addLocalDemoGift(account: self.account, peerId: peerId, gift: value, text: event.comment,
                syncAuthorId: authorId, syncTimestamp: Int32(clamping: event.created), syncUniqueId: uniqueId, synchronize: false)
                |> deliverOnMainQueue).start(completed: { [weak self] in
                    self?.importEvents(events, index: index + 1, previousSequence: event.seq, completion: completion)
                }))
        }))
    }
}
