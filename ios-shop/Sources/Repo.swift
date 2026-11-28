import Foundation
import SwiftUI

/** Live product repository: fetches dressjet.com public JSON, caches the last good read.
 *  Android Repo.kt parity: full-catalog read (a new Shopify listing surfaces by itself),
 *  poster-enriched parses (video-only products get their real website poster; a product
 *  with no website visual at all is still dropped), homepage rails, hero discovery with
 *  the verified 4 Nov assets as fallback, per-handle video answers for grid tiles. */
@MainActor final class Repo: ObservableObject {
    @Published private(set) var products: [DjProduct] = [] { didSet { recomputeDerived() } }
    @Published private(set) var collections: [DjCollection] = []
    /** Homepage rails: collection metadata paired with its products. Missing/failed
     *  sections are omitted, never substituted (website fields only). */
    @Published private(set) var sections: [(DjCollection, [DjProduct])] = [] { didSet { recomputeDerived() } }
    /** Homepage hero video/poster, discovered from the live homepage HTML with the
     *  verified 4 Nov assets as fallback. */
    @Published private(set) var hero = HeroMedia(video: Feed.FALLBACK_HERO_VIDEO, poster: Feed.FALLBACK_HERO_POSTER)
    @Published private(set) var loaded = false
    @Published private(set) var failed = false
    /** Endless-feed paging state: more pages remain until a short/empty page. The full
     *  250-limit first read usually exhausts the catalog, so this starts done. */
    @Published private(set) var catalogDone = false
    @Published private(set) var loadingMore = false
    private var nextPage = 1
    private var loadingPage = false
    private var videoCache: [String: DjVideo?] = [:]
    private var catCache: [String: [DjProduct]] = [:]
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let cached = defaults.data(forKey: "djshop.products") {
            // The cached raw predates poster enrichment: keep the shipped cold-start
            // rule (no image, no tile) until refresh lands the enriched list.
            let list = Feed.parseProducts(cached).filter { !$0.images.isEmpty }
            if !list.isEmpty { products = list }
        }
        if let cached = defaults.data(forKey: "djshop.collections") {
            let cols = Feed.parseCollections(cached)
            if !cols.isEmpty { collections = cols }
        }
        if let cached = defaults.data(forKey: "djshop.homeOrder") { homeOrder = Feed.parseHomeOrder(cached) }
        recomputeDerived()
    }

    /** "Latest In": the WHOLE catalog, newest first, one continuous scroll.
     *  234: computed once per products/sections change (Arsh 10:36 PM: stuttery scroll -
     *  the whole catalog was re-sorted on EVERY view evaluation, and each video answer
     *  forced one via a global tick). */
    @Published private(set) var latestIn: [DjProduct] = []

    /** Endless grid source: catalog minus rail and Latest In items, newest-first. */
    @Published private(set) var gridProducts: [DjProduct] = []

    /** Owner-set order from Firestore config/homeOrder (nil = newest first, as before). */
    @Published private(set) var homeOrder: Feed.HomeOrder? = nil { didSet { recomputeDerived() } }

    private func recomputeDerived() {
        let latest = Feed.arranged(products, homeOrder)
        latestIn = latest
        let hidden = homeOrder?.hidden ?? []
        gridProducts = Feed.remainingProducts(products, sections.flatMap { $0.1 } + latest)
            .filter { !hidden.contains($0.handle) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /** One read of the order document. Any failure keeps the last good order (cached) or none. */
    private func refreshHomeOrder() async {
        var req = URLRequest(url: Feed.homeOrderURL)
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData // 322: never a stale copy
        req.timeoutInterval = 8
        if let (data, resp) = try? await URLSession.shared.data(for: req), let http = resp as? HTTPURLResponse {
            if http.statusCode == 200, let o = Feed.parseHomeOrder(data) {
                homeOrder = o
                defaults.set(data, forKey: "djshop.homeOrder")
            } else if http.statusCode == 404 {
                homeOrder = nil
                defaults.removeObject(forKey: "djshop.homeOrder")
            }
        }
    }

    /** 322: called each time the app becomes active, so a saved order shows without a cold start. */
    func refreshOrder() { Task { await refreshHomeOrder() } }

    /** Test seam: inject already-parsed products without network. */
    func seed(_ list: [DjProduct]) { products = list; loaded = true; failed = false }

    func peekCollection(_ handle: String) -> [DjProduct]? { catCache[handle] }

    /** One collection's products, one fetch per collection, cached for the session.
     *  ALL_HANDLE reads the full catalog. 236: only a non-empty answer is cached - a
     *  failed read used to stick as an empty cache entry and the menu category stayed
     *  blank for the whole session (Arsh 3:19 PM). */
    func loadCollection(_ handle: String) async {
        if catCache[handle] != nil { return }
        let url = handle == Feed.ALL_HANDLE ? Feed.productsURL : Feed.collectionProductsURL(handle)
        if let list = try? await Self.fetchProducts(url), !list.isEmpty {
            catCache[handle] = list
        }
    }

    func peekVideo(_ handle: String) -> DjVideo? { videoCache[handle] ?? nil }
    func hasVideoAnswer(_ handle: String) -> Bool { videoCache.keys.contains(handle) }

    /** A product's own site video, resolved lazily per visible tile / PDP open and cached
     *  for the session. Null answer = the site has none (still cached, no refetch). */
    func loadVideo(_ handle: String) async {
        if videoCache.keys.contains(handle) { return }
        let v = (try? await Self.get(Feed.productJsURL(handle))).flatMap { Feed.parseProductVideo($0) }
        videoCache[handle] = v
    }

    func refresh() {
        Task {
            await refreshHomeOrder()
            do {
                let raw = try await Self.get(Feed.productsURL)
                let list = try await Self.enrich(Feed.parseProducts(raw))
                if !list.isEmpty {
                    products = list
                    nextPage = 2
                    catalogDone = true // the 250-limit read covers the whole catalog today
                    defaults.set(raw, forKey: "djshop.products")
                    failed = false
                }
                await refreshSections()
                await refreshHero()
                loaded = true
                prefetchVideos()
            } catch {
                failed = products.isEmpty
                loaded = true
            }
        }
    }

    /** Endless scroll: fetch the next catalog page. No-op while a page is in flight or the
     *  catalog is exhausted. Unknown stays unknown: a failed page just isn't appended. */
    func loadMoreCatalog() {
        if catalogDone || loadingPage { return }
        loadingPage = true
        loadingMore = true
        Task {
            let page = nextPage
            if let list = try? await Self.fetchProducts(Feed.productsPageURL(page)) {
                if list.isEmpty || list.count < 30 { catalogDone = true }
                if !list.isEmpty {
                    products = Feed.mergeProducts(products, list)
                    nextPage += 1
                }
            } // else: scroll again to retry
            loadingPage = false
            loadingMore = false
        }
    }

    /** Resolve video answers for the newest pieces right after the catalog lands so the
     *  grid tiles can play instantly. (Android also byte-warms an on-disk cache; iOS has
     *  no equivalent layer yet - AVPlayer streams from the CDN on first play.) */
    private func prefetchVideos() {
        Task {
            for p in Feed.newest(products, 24) where !videoCache.keys.contains(p.handle) {
                let v = (try? await Self.get(Feed.productJsURL(p.handle))).flatMap { Feed.parseProductVideo($0) }
                videoCache[p.handle] = v
            }
        }
    }

    /** Discover the current site hero video from the homepage HTML; fallbacks stay. */
    private func refreshHero() async {
        if let data = try? await Self.get(Feed.homeURL),
           let html = String(data: data, encoding: .utf8),
           let media = Feed.parseHeroMedia(html), media.video != nil {
            hero = media
        }
    }

    /** Collections + homepage rails. Best-effort: a failed section drops out of the home
     *  page instead of blocking the catalog. */
    private func refreshSections() async {
        guard let data = try? await Self.get(Feed.collectionsURL) else { return }
        let cols = Feed.parseCollections(data)
        guard !cols.isEmpty else { return }
        collections = cols
        defaults.set(data, forKey: "djshop.collections")
        var built: [(DjCollection, [DjProduct])] = []
        for handle in Feed.HOME_SECTION_HANDLES {
            guard let meta = cols.first(where: { $0.handle == handle }) else { continue }
            // 236: seed the menu category cache from the rail read - Jackets / Polos /
            // Shoes open instantly instead of refetching.
            if let prods = try? await Self.fetchProducts(Feed.collectionProductsURL(handle)), !prods.isEmpty {
                built.append((meta, prods))
                catCache[handle] = prods
            }
        }
        sections = built
    }

    /** Parse + poster-enrich: video-only products get their real website poster; a product
     *  with no website visual at all is still dropped. */
    private static func fetchProducts(_ url: URL) async throws -> [DjProduct] {
        let raw = try await get(url)
        return try await enrich(Feed.parseProducts(raw))
    }

    /** Poster-enrich: video-only products get their real website poster; a product with
     *  no website visual at all is still dropped. */
    private static func enrich(_ parsed: [DjProduct]) async throws -> [DjProduct] {
        var out: [DjProduct] = []
        for p in parsed {
            if !p.images.isEmpty { out.append(p); continue }
            if let js = try? await get(Feed.productJsURL(p.handle)),
               let poster = Feed.parseMediaPoster(js) {
                out.append(DjProduct(id: p.id, handle: p.handle, title: p.title, type: p.type,
                                     images: [poster], variants: p.variants,
                                     createdAt: p.createdAt, description: p.description))
            }
        }
        return out.filter { !$0.images.isEmpty }
    }

    private static func get(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: req)
        return data
    }
}

/** Bag: UserDefaults-persisted cart. */
@MainActor final class Bag: ObservableObject {
    @Published private(set) var lines: [Feed.BagLine] = []
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "djshop.bag"),
           let stored = try? JSONDecoder().decode([Feed.BagLine].self, from: data) {
            lines = stored
        }
    }

    var count: Int { lines.reduce(0) { $0 + $1.qty } }
    var totalPaise: Int64 { lines.reduce(0) { $0 + Feed.paise($1.price) * Int64($1.qty) } }
    /** Bag total, paise-aware: a ₹x.99 line no longer truncates to ₹x (Feed.inr parity). */
    var totalInr: String {
        let whole = totalPaise / 100
        let rem = Int(totalPaise % 100)
        let grouped = Feed.indianGroup(whole)
        return rem == 0 ? "₹" + grouped : "₹" + grouped + "." + String(format: "%02d", rem)
    }

    func add(_ p: DjProduct, _ v: DjVariant) {
        if let ix = lines.firstIndex(where: { $0.variantId == v.id }) {
            lines[ix].qty += 1
        } else {
            lines.append(Feed.BagLine(variantId: v.id, handle: p.handle, title: p.title,
                                      size: v.title, price: v.price, image: p.images.first ?? "", qty: 1))
        }
        write()
    }

    func remove(_ variantId: Int64) {
        lines.removeAll { $0.variantId == variantId }
        write()
    }

    var json: String { String(data: (try? JSONEncoder().encode(lines)) ?? Data("[]".utf8), encoding: .utf8) ?? "[]" }

    /** Account sign-in: union of the phone's bag and the saved one (higher quantity wins per item). */
    func mergeRemote(_ raw: String) {
        guard !raw.isEmpty, let remote = try? JSONDecoder().decode([Feed.BagLine].self, from: Data(raw.utf8)) else { return }
        for r in remote {
            if let ix = lines.firstIndex(where: { $0.variantId == r.variantId }) { lines[ix].qty = max(lines[ix].qty, r.qty) }
            else { lines.append(r) }
        }
        defaults.set(try? JSONEncoder().encode(lines), forKey: "djshop.bag")
    }

    private func write() {
        defaults.set(try? JSONEncoder().encode(lines), forKey: "djshop.bag")
        Account.shared.bagChanged()
    }
}
