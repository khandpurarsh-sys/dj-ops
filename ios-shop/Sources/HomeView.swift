import SwiftUI
import AVFoundation

/** Homepage (Android HomeScreen.kt parity): sticky frosted search header whose ink adapts
 *  video -> white, full-screen website hero video, "Latest In" (the whole catalog, newest
 *  first, 2-col), curated rails (all-new-jackets / polos / shoes / trousers; empty
 *  collections omitted), then any remaining products as an endless lazy-paged 2-col feed
 *  with a quiet gold end note. Website data only; selling price only; rails are deduped
 *  out of the grid; no-photo products are skipped by Repo. */
struct HomeView: View {
    @ObservedObject var repo: Repo
    let bagCount: Int
    @ObservedObject var bag: Bag
    /** Reports the dock flip rule upward: true while the hero's bottom edge is still
     *  clear of the dock (dockStaysGlass), so RootView can restyle the dock. */
    @Binding var dockGlass: Bool
    /** Bottom Menu pill minimises while scrolling down, expands on scroll up (iOS tab-bar minimise). */
    @Binding var dockMini: Bool
    /** Dock only exists once the hero's white edge has started to rise into view. */
    @Binding var dockVisible: Bool
    /** 236: id of the topmost feed row, owned by RootView so it survives the product
     *  page - Back restores the feed where it was (Arsh 3:19/3:21 PM). */
    @Binding var scrollId: String?
    let onBag: () -> Void
    let onSearch: () -> Void
    let onDiscover: () -> Void
    let onProduct: (DjProduct) -> Void

    /** 220b: raw offset lives in a plain box - writing @State every frame re-evaluated the
     *  whole feed on each scroll tick (the jank). State only changes on threshold flips. */
    private final class ScrollBox { var offset: CGFloat = 0; var seen = false; var lastMove = Date.distantPast; var inset: CGFloat? = nil; var anchor: CGFloat = 0 }
    @State private var box = ScrollBox()
    @State private var onHero = true
    /** 220-ios: true while the feed moves and ~0.22s after; tile players hold off. */
    @State private var feedScrolling = false
    @State private var settleTask: Task<Void, Never>? = nil
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geo in
            // 224: hero is the FULL screen. geo can exclude the bottom safe area (his video showed a white
            // strip under the hero at rest), so size from the screen itself.
            let heroH = max(geo.size.height, UIScreen.main.bounds.height)
            ZStack(alignment: .top) {
                Color.white.ignoresSafeArea()
                if !repo.loaded {
                    VStack { Spacer(); Text("Loading…").font(Dj.assistant(13)).foregroundStyle(Dj.ink3); Spacer() }
                } else if repo.failed {
                    VStack {
                        Spacer()
                        Text("Could not load the collection.").font(Dj.assistant(14)).foregroundStyle(Dj.ink2)
                        Button("T A P   T O   R E T R Y") { repo.refresh() }
                            .font(Dj.assistant(11.5, weight: .semibold)).tracking(3)
                            .foregroundStyle(Dj.navy).padding(.top, 16)
                        Spacer()
                    }
                } else {
                    feed(heroH: heroH)
                }
                HomeSearchHeader(dark: onHero, bagCount: bagCount, onSearch: onSearch, onBag: onBag)
            }
        }
        .ignoresSafeArea() // 223: hero is edge to edge (white strip under it on his 2:10 AM video)
    }

    private func feed(heroH: CGFloat) -> some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: []) {
                HeroVideoView(hero: repo.hero, active: scenePhase == .active && onHero, onShopNow: onDiscover)
                    .frame(maxWidth: .infinity).frame(height: heroH)
                    .id("hero")
                let chunks = Feed.feedChunks({ var seen = Set<Int64>(); return (repo.latestIn + repo.gridProducts).filter { seen.insert($0.id).inserted } }(), ownerOrdered: !(repo.homeOrder?.order.isEmpty ?? true))
                ForEach(Array(chunks.enumerated()), id: \.offset) { ci, chunk in
                    EditorialChunk(chunk: chunk, index: ci, bag: bag, onProduct: onProduct)
                        .id("chunk-\(chunk.first?.id ?? 0)")
                        .onAppear { if ci >= chunks.count - 2 { repo.loadMoreCatalog() } }
                }
                endNote.id("end")
                Spacer().frame(height: 110 + (UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.keyWindow?.safeAreaInsets.bottom ?? 0))
                    .id("tail")
            }
            .scrollTargetLayout()
            .background(GeometryReader { p in
                Color.clear.preference(key: HomeScrollKey.self, value: -p.frame(in: .named("homeScroll")).minY)
            })
        }
        .scrollPosition(id: $scrollId)
        .background(UIScrollObserver { apply($0, heroH: heroH) })
        .coordinateSpace(name: "homeScroll")
        .onPreferenceChange(HomeScrollKey.self) { apply($0, heroH: heroH) }
        .modifier(ScrollOffsetTap { apply($0, heroH: heroH) })
        .environment(\.djFeedScrolling, feedScrolling)
        .scrollIndicators(.hidden)
    }

    /** One entry for every scroll-offset source (preference + iOS 18 scroll geometry), so
     *  the dock flip can never depend on a single signal. */
    private func apply(_ raw: CGFloat, heroH: CGFloat) {
        let off = max(0, raw)
        // 235: three independent sources (preference, UIScrollView KVO, iOS 18 geometry) all
        // report EVERY frame; only the first per frame does work now.
        if box.seen, abs(off - box.offset) <= 0.5 { return }
        box.seen = true
        if abs(off - box.offset) > 0.5 {
            box.lastMove = Date()
            if !feedScrolling {
                feedScrolling = true
                settleTask?.cancel()
                settleTask = Task { @MainActor in
                    while Date().timeIntervalSince(box.lastMove) < 0.22 {
                        try? await Task.sleep(nanoseconds: 80_000_000)
                        if Task.isCancelled { return }
                    }
                    feedScrolling = false
                }
            }
        }
        box.offset = off
        // Dock appears after the hero video: once the white line starts (hero bottom edge above the screen bottom).
        if off > 12 { if !dockVisible { dockVisible = true } }
        else if off < 4 { if dockVisible { dockVisible = false }; if dockMini { dockMini = false } }
        // Tab-bar minimise: anchor follows the extreme of the current direction; flip on a small reversal.
        if off < 24 {
            box.anchor = off
            if dockMini { dockMini = false }
        } else if dockMini {
            box.anchor = max(box.anchor, off)
            if box.anchor - off > 12 { dockMini = false; box.anchor = off }
        } else {
            box.anchor = min(box.anchor, off)
            if off - box.anchor > 18 { dockMini = true; box.anchor = off }
        }
        // 224: header turns solid white only once the hero's bottom edge is above the header band,
        // so no video shows behind the white wordmark/search (his ghosting frames).
        let nowOnHero = off < heroH - 190
        if nowOnHero != onHero { onHero = nowOnHero }
        // 223: flip when the hero's bottom edge reaches the dock's TOP (dock = 18pt float + ~48pt
        // capsule + bottom safe inset), not 40pt from the screen edge - that was too late.
        // 235: the window lookup ran every frame; it only needs resolving once.
        if box.inset == nil {
            let i = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.keyWindow?.safeAreaInsets.bottom ?? 0
            if i > 0 { box.inset = i }
        }
        let bottomInset = box.inset ?? 0
        let glass = dockStaysGlass(heroBottom: heroH - off, viewportEnd: heroH, dockTouchPx: 66 + bottomInset)
        if glass != dockGlass {
            dockGlass = glass
            DjDiag.log("dock " + (glass ? "glass" : "solid") + " off=\(Int(off))")
        }
    }

    private func gridRows(_ products: [DjProduct], keyPrefix: String) -> some View {
        let rows = stride(from: 0, to: products.count, by: 2).map { Array(products[$0..<min($0 + 2, products.count)]) }
        return ForEach(Array(rows.enumerated()), id: \.offset) { ix, row in
            HStack(alignment: .top, spacing: 16) {
                ForEach(row) { p in
                    GridCard(product: p, repo: repo, onTap: { onProduct(p) })
                        .frame(maxWidth: .infinity)
                }
                if row.count == 1 { Spacer().frame(maxWidth: .infinity) }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
            .id("\(keyPrefix)-\(row.first?.id ?? 0)")
            .onAppear {
                // Endless feed: the last rows approaching the viewport pull the next page.
                // 224: warm the next 4 rows' photos so tiles are not blank white when they arrive.
                // 235: 10 rows ahead (was 4) at the width the tile actually uses (560).
                for nxt in rows.dropFirst(ix + 1).prefix(10).flatMap({ $0 }) {
                    if let u = nxt.images.first, DjImageLoader.shared.cached(u, 560) == nil {
                        Task.detached(priority: .utility) { _ = await DjImageLoader.shared.load(u, 560) }
                    }
                }
                if keyPrefix == "row" || keyPrefix == "lrow", ix >= rows.count - 3 {
                    repo.loadMoreCatalog()
                }
            }
        }
    }

    private var endNote: some View {
        Group {
            if repo.catalogDone {
                VStack(spacing: 12) {
                    Rectangle().fill(Dj.gold).frame(width: 52, height: 1)
                    Text("DRESSJET")
                        .font(Dj.cinzel(8.5)).tracking(4)
                        .foregroundStyle(Dj.gold.opacity(0.7))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 34)
            } else {
                Text("· · ·").font(.system(size: 16)).foregroundStyle(Dj.gold)
                    .frame(maxWidth: .infinity).padding(.vertical, 30)
            }
        }
    }
}

private struct HomeScrollKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/** Sticky frosted search bar + bag. Ink adapts video -> white with a 280ms ease. */
private struct HomeSearchHeader: View {
    let dark: Bool
    let bagCount: Int
    let onSearch: () -> Void
    let onBag: () -> Void
    var body: some View {
        let ink = dark ? Dj.cream : Dj.navy
        VStack(spacing: 10) {
        Wordmark(color: ink)
        HStack(spacing: 12) {
            FrostedPill(dark: dark, action: onSearch) {
                HStack(spacing: 10) {
                    Text("⌕").font(.system(size: 16)).foregroundStyle(ink)
                    Text("Search DressJet")
                        .font(Dj.assistant(14, weight: .medium))
                        .foregroundStyle(ink.opacity(0.88))
                    Spacer()
                }
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity).frame(height: 46)
            }
            Button(action: onBag) {
                BagIcon(count: bagCount, tint: ink)
                    .frame(width: 38, height: 38)
                    .background(dark ? Color.white.opacity(0.26) : Color.white.opacity(0.55), in: Circle())
                    .overlay(Circle().stroke(dark ? Color.white.opacity(0.55) : Dj.navy.opacity(0.10), lineWidth: 1))
            }
        }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24 + (UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.keyWindow?.safeAreaInsets.top ?? 0))
        .padding(.bottom, 10)
        .background(dark ? Color.clear : Color.white, ignoresSafeAreaEdges: .top)
        .animation(.easeOut(duration: 0.28), value: dark)
    }
}

/** Section headline: small gold wordmark eyebrow, Cormorant italic 38, thin right arrow. */
struct RailHeader: View {
    let title: String
    var trailing: String = "→"
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: "DressJet", color: Dj.gold.opacity(0.8))
            HStack {
                SerifTitle(text: title, color: Dj.navy, size: 38)
                Spacer()
                Text(trailing)
                    .font(Dj.assistant(trailing == "→" ? 22 : 12))
                    .foregroundStyle(trailing == "→" ? Dj.navy : Dj.ink3)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 34).padding(.bottom, 14)
    }
}

/** Horizontal curated rail: 150-wide photo cards, name + selling price. */
private struct HomeRail: View {
    let title: String
    let products: [DjProduct]
    let onProduct: (DjProduct) -> Void
    var body: some View {
        VStack(spacing: 0) {
            RailHeader(title: title)
            ScrollView(.horizontal) {
                LazyHStack(spacing: 14) {
                    ForEach(products) { p in
                        Button { onProduct(p) } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                DjImage(url: p.images.first ?? "", widthPx: 450)
                                    .frame(width: 150, height: 200)
                                    .clipShape(RoundedRectangle(cornerRadius: Dj.tileRadius))
                                Spacer().frame(height: 8)
                                Text(Feed.displayTitle(p.title))
                                    .font(Dj.cormorant(17)).lineSpacing(2)
                                    .foregroundStyle(Dj.navy).lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Spacer().frame(height: 2)
                                Text(Feed.priceLabel(p))
                                    .font(Dj.assistant(13, weight: .medium))
                                    .foregroundStyle(Dj.ink2)
                            }
                            .frame(width: 150)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
        }
    }
}

/** Grid card: photo aspect 174:224 radius 3; name Cormorant 21/23.5; price 12, 7 below.
 *  Tiles play the product video like the website (muted loop) once its answer resolves;
 *  the poster paints first either way. DjAnim.enabled = no autoplay, no resolving. */
struct GridCard: View {
    let product: DjProduct
    let repo: Repo
    let onTap: () -> Void

    @State private var video: DjVideo? = nil

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                // 220-ios: the tile's box is fixed by Color.clear (33:44 from the column
                // width) and the content is only an OVERLAY clipped to it. Before, the
                // fill aspect ratio sat on flexible children and a video layer could grow
                // past its column (his giant black blocks on the 9:36 PM fling).
                Color.clear
                    .aspectRatio(33.0 / 44.0, contentMode: .fit)
                    .overlay {
                        Group {
                            if let video {
                                TileVideoView(video: video, posterFallback: product.images.first)
                            } else {
                                DjImage(url: product.images.first ?? "", widthPx: 560)
                            }
                        }
                        .clipped()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Dj.tileRadius))
                Spacer().frame(height: 8)
                Text(Feed.displayTitle(product.title))
                    .font(Dj.cormorant(21)).lineSpacing(2.5)
                    .foregroundStyle(Dj.navy).lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer().frame(height: 7)
                Text(Feed.priceLabel(product))
                    .font(Dj.assistant(12, weight: .medium))
                    .foregroundStyle(Dj.ink2)
            }
        }
        .buttonStyle(.plain)
        .task {
            guard DjAnim.enabled else { return }
            // 220-ios: hold video lookups until 1.5s after launch (images first).
            let wait = DjLaunch.t0.addingTimeInterval(1.5).timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1e9)) }
            if !repo.hasVideoAnswer(product.handle) { await repo.loadVideo(product.handle) }
            video = repo.peekVideo(product.handle)
        }
    }
}

/** At most MAX concurrent tile players; the rest keep the poster (scroll smoothness). */
enum DjPlayerBudget {
    static let max = 3
    private static var inUse = 0
    private static let lock = NSLock()
    static func tryAcquire() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if inUse < max { inUse += 1; return true }
        return false
    }
    static func release() {
        lock.lock(); defer { lock.unlock() }
        if inUse > 0 { inUse -= 1 }
    }
}

/** Shared muted-loop player holder: poster stays on top until the item is ready to play -
 *  no black flash, instant paint. Released with the view. */
@MainActor final class LoopPlayer: ObservableObject {
    @Published private(set) var ready = false
    @Published private(set) var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var obs: NSKeyValueObservation?
    private let budgeted: Bool
    private let url: String
    private var holdsSlot = false
    private var local: URL? = nil
    private var bundledFile: URL? = nil

    /** 220b: tile clips are small mp4s - fetch to the caches dir and play the LOCAL file
     *  (Android DjVideoCache parity); the remote stream stalled on cellular. Failure just
     *  leaves the remote URL in place. */
    func prefetch(force: Bool = false) async {
        if local != nil || (!budgeted && !force) { return }
        guard let u = URL(string: url) else { return }
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("djvid")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = String(url.split(separator: "/").last ?? "v").replacingOccurrences(of: "/", with: "_") + ".mp4"
        let dest = dir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: dest.path) { local = dest; return }
        if let (tmp, resp) = try? await URLSession.shared.download(from: u),
           (resp as? HTTPURLResponse)?.statusCode == 200 {
            try? FileManager.default.removeItem(at: dest)
            if (try? FileManager.default.moveItem(at: tmp, to: dest)) != nil { local = dest }
        } else { DjDiag.log("vid dl fail " + String(url.split(separator: "/").last?.prefix(20) ?? "")) }
    }

    /** lazy = true: nothing is built until ensurePlayer() (tiles build only once the
     *  feed is settled, never mid-fling). Hero passes lazy = false: built immediately. */
    init(url: String, active: Bool, budgeted: Bool, lazy: Bool = false, bundled: URL? = nil) {
        self.budgeted = budgeted
        self.url = url
        self.bundledFile = bundled
        if !lazy { build(active: active) }
    }

    /** Returns false when a budgeted tile has no free slot yet (caller retries). */
    @discardableResult func ensurePlayer() -> Bool {
        if player != nil { return true }
        if budgeted {
            guard DjPlayerBudget.tryAcquire() else { return false }
            holdsSlot = true
        }
        build(active: true)
        return player != nil
    }

    private func build(active: Bool) {
        guard let remote = URL(string: url) else { return }
        let u = bundledFile ?? local ?? remote
        let item = AVPlayerItem(url: u)
        let q = AVQueuePlayer(playerItem: item)
        q.isMuted = true
        q.actionAtItemEnd = .none
        looper = AVPlayerLooper(player: q, templateItem: item)
        player = q
        let tag = String(url.split(separator: "/").last?.prefix(24) ?? "")
        obs = item.observe(\.status, options: [.new]) { [weak self] it, _ in
            if it.status == .readyToPlay {
                Task { @MainActor in self?.ready = true }
            } else if it.status == .failed {
                let why = (it.error as NSError?).map { "\($0.domain.suffix(12)) \($0.code)" } ?? "?"
                Task { @MainActor in DjDiag.log("vid \(tag) \(why)") }
            }
        }
        if active { q.play() }
    }

    func setActive(_ active: Bool) {
        wantActive = active
        if active { player?.play() } else { player?.pause() }
    }

    private var wantActive = true
    private var stallTimer: Task<Void, Never>? = nil

    /** Hero only: while the poster shows, fetch the clip to the caches dir; if the remote stream has
     *  not become ready by then (cellular stall, his "hero not loading"), rebuild on the LOCAL file.
     *  A stalled or failed remote item is also rebuilt after 6 s. Later launches hit the cache. */
    func heroUpgradeToLocal() async {
        if bundledFile != nil { return }
        await prefetch(force: true)
        guard local != nil, !ready else { return }
        rebuildLocal()
    }
    func heroWatchdog() async {
        if bundledFile != nil { return }
        try? await Task.sleep(nanoseconds: 6_000_000_000)
        if !ready, local == nil { await prefetch(force: true) }
        if !ready, local != nil { rebuildLocal() }
    }
    private func rebuildLocal() {
        player?.pause()
        looper = nil; obs = nil; player = nil
        build(active: wantActive)
    }

    /** Free the decoder + budget slot (watchdog fallback and teardown). */
    func release() {
        player?.pause()
        looper = nil; obs = nil; player = nil; ready = false
        if holdsSlot { DjPlayerBudget.release(); holdsSlot = false }
    }

    deinit {
        // MainActor-isolated state cannot be touched here; the slot is returned by
        // release(), which TileVideoView calls on disappear.
    }
}

/** AVPlayerLayer-backed video surface (resizeAspectFill, no chrome). */
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer?
    func makeUIView(context: Context) -> PlayerLayerUIView {
        let v = PlayerLayerUIView()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ uiView: PlayerLayerUIView, context: Context) {
        uiView.playerLayer.player = player
    }
}

final class PlayerLayerUIView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

/** Grid-tile video: the poster is ALREADY on screen from the product photo; the player
 *  is built only once the feed has settled (220-ios), its layer is hidden while the
 *  feed moves, and a tile with no first frame 2.5s after settling falls back to the
 *  plain photo and frees its slot (the stuck-black-tile guard). */
struct TileVideoView: View {
    let video: DjVideo
    let posterFallback: String?
    @StateObject private var holder: LoopPlayer
    @Environment(\.djFeedScrolling) private var scrolling
    @State private var gaveUp = false

    init(video: DjVideo, posterFallback: String?) {
        self.video = video
        self.posterFallback = posterFallback
        _holder = StateObject(wrappedValue: LoopPlayer(url: video.url, active: false,
                                                       budgeted: true, lazy: true))
    }

    private var posterURL: String { posterFallback ?? video.poster ?? "" }

    var body: some View {
        ZStack {
            if gaveUp {
                DjImage(url: posterFallback ?? video.poster ?? "", widthPx: 560)
            } else {
                if let p = holder.player, !scrolling { PlayerLayerView(player: p).allowsHitTesting(false) }
                if !holder.ready || scrolling { DjImage(url: posterURL, widthPx: 560) }
            }
        }
        .clipped()
        .task(id: scrolling) {
            if scrolling { holder.setActive(false); return }
            await holder.prefetch()
            if Task.isCancelled { return }
            while !gaveUp && !holder.ensurePlayer() {
                try? await Task.sleep(nanoseconds: 200_000_000)
                if Task.isCancelled { return }
            }
            holder.setActive(true)
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if Task.isCancelled { return }
            if !holder.ready && !gaveUp {
                DjDiag.log("vid slow " + String(video.url.split(separator: "/").last?.prefix(24) ?? ""))
                holder.release()
                gaveUp = true
            }
        }
        .onDisappear { holder.release() }
    }
}

/** Homepage hero: the dressjet.com hero video, played like the website does - muted,
 *  looping, full-bleed, autoplaying the moment home is active - with the site's own
 *  poster behind it until readiness. The known hero asset carries a baked-in DRESSJET
 *  wordmark in its top ~14%; the fill crop removes that band (the app's header owns the
 *  top of the screen). Unknown future hero videos get a plain centered crop. The only
 *  overlay is "Shop Now" (website parity), frosted glass showing the video beneath. */
struct HeroVideoView: View {
    let hero: HeroMedia
    let active: Bool
    let onShopNow: () -> Void

    private static let logoBand: CGFloat = 0.14
    private var knownAsset: Bool { hero.video == nil || hero.video == Feed.FALLBACK_HERO_VIDEO }
    private var stream: String {
        hero.video720 ?? hero.video ??
            Feed.FALLBACK_HERO_VIDEO.replacingOccurrences(of: "HD-1080p-7.2Mbps", with: "HD-720p-4.5Mbps")
    }
    private var playing: Bool { active && hero.video != nil }
    /** The known hero clip ships inside the app (re-encoded 606x1080, ~3 MB): instant first frame and
     *  playback with no network. A different live hero falls back to the remote stream path. */
    private var bundledClip: URL? { knownAsset ? Bundle.main.url(forResource: "hero_bundled", withExtension: "mp4") : nil }
    private var bundledPoster: UIImage? {
        guard knownAsset, let p = Bundle.main.path(forResource: "hero_poster", ofType: "jpg") else { return nil }
        return UIImage(contentsOfFile: p)
    }

    var body: some View {
        GeometryReader { geo in
            let band: CGFloat = knownAsset ? Self.logoBand : 0
            let windowH = geo.size.height
            let childH = band > 0 ? windowH / (1 - band) : windowH
            // 225: TOP-aligned. A default (centred) ZStack let the taller-than-window child
            // overflow equally top and bottom, so after the -topCrop offset the media ended
            // band*childH/2 (~76pt on a 932pt screen) ABOVE the bottom edge = his light strip.
            ZStack(alignment: .top) {
                if playing {
                    HeroPlayer(url: stream, poster: hero.poster ?? Feed.FALLBACK_HERO_POSTER,
                               active: active, height: childH, topCrop: band * childH,
                               bundled: bundledClip, bundledPoster: bundledPoster)
                } else {
                    Group {
                        if let bp = bundledPoster {
                            Image(uiImage: bp).resizable().scaledToFill()
                        } else {
                            DjImage(url: hero.poster ?? Feed.FALLBACK_HERO_POSTER, widthPx: 1200)
                        }
                    }
                    .frame(width: geo.size.width, height: childH)
                    .clipped()
                    .offset(y: band > 0 ? -band * childH : 0)
                }
            }
            .frame(width: geo.size.width, height: windowH, alignment: .top)
            .clipped()
        }
        .overlay(alignment: .bottom) {
            FrostedPill(dark: true, action: onShopNow) {
                Text("S H O P   N O W")
                    .font(Dj.assistant(11.5, weight: .semibold)).tracking(3)
                    .foregroundStyle(Dj.cream)
                    .padding(.horizontal, 34).padding(.vertical, 13)
            }
            .padding(.bottom, 108)
            .visualEffect { c, proxy in
                let y = proxy.frame(in: .global).minY
                return c.opacity(max(0, min(1, (y - 190) / 120)))
            }
        }
    }
}

private struct HeroPlayer: View {
    let url: String
    let poster: String
    let active: Bool
    let height: CGFloat
    let topCrop: CGFloat
    let bundledPoster: UIImage?
    @StateObject private var holder: LoopPlayer

    init(url: String, poster: String, active: Bool, height: CGFloat, topCrop: CGFloat, bundled: URL? = nil, bundledPoster: UIImage? = nil) {
        self.url = url; self.poster = poster; self.active = active
        self.height = height; self.topCrop = topCrop
        self.bundledPoster = bundledPoster
        _holder = StateObject(wrappedValue: LoopPlayer(url: url, active: active, budgeted: false, bundled: bundled)) // hero plays outside the 4-tile budget
    }

    var body: some View {
        ZStack(alignment: .top) {
            if let p = holder.player { PlayerLayerView(player: p) }
            if !holder.ready {
                if let bp = bundledPoster { Image(uiImage: bp).resizable().scaledToFill().frame(maxWidth: .infinity).frame(height: height).clipped() }
                else { DjImage(url: poster, widthPx: 1200) }
            }
        }
        .frame(maxWidth: .infinity).frame(height: height)
        .offset(y: topCrop > 0 ? -topCrop : 0)
        .onChange(of: active) { _, now in holder.setActive(now) }
        .task { await holder.heroUpgradeToLocal() }
        .task { await holder.heroWatchdog() }
    }
}

/** iOS 18+: read the scroll offset straight from the ScrollView (second, independent source
 *  next to the background-preference one). No-op on iOS 17. */
private struct ScrollOffsetTap: ViewModifier {
    let onOffset: (CGFloat) -> Void
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y + $0.contentInsets.top }) { _, new in
                onOffset(new)
            }
        } else { content }
    }
}

/** Third scroll signal, works on every iOS: finds the enclosing UIScrollView and KVO-observes
 *  contentOffset. Placed as a background of the ScrollView, it climbs from its own
 *  (sibling-to-content) view to the scroll view via the superview chain once attached. */
private struct UIScrollObserver: UIViewRepresentable {
    let onOffset: (CGFloat) -> Void
    func makeUIView(context: Context) -> ProbeView { let v = ProbeView(); v.onOffset = onOffset; return v }
    func updateUIView(_ v: ProbeView, context: Context) { v.onOffset = onOffset }

    final class ProbeView: UIView {
        var onOffset: ((CGFloat) -> Void)?
        private var obs: NSKeyValueObservation?
        private weak var found: UIScrollView?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { obs = nil; found = nil; return }
            DispatchQueue.main.async { [weak self] in self?.attach() }
        }
        private func attach() {
            guard found == nil, let root = window else { return }
            // Background views are siblings of the scroll view's hosting layer: search the
            // ancestors' subtree for the biggest vertical UIScrollView under our window.
            var node: UIView? = self
            while let n = node, found == nil {
                found = Self.scroll(in: n)
                node = n.superview
            }
            _ = root
            guard let sv = found else { return }
            obs = sv.observe(\.contentOffset, options: [.new]) { [weak self] s, _ in
                let y = s.contentOffset.y + s.adjustedContentInset.top
                DispatchQueue.main.async { self?.onOffset?(y) }
            }
        }
        private static func scroll(in v: UIView) -> UIScrollView? {
            if let s = v as? UIScrollView, s.bounds.height > 300, s.contentSize.height > s.bounds.height { return s }
            for c in v.subviews { if let s = scroll(in: c) { return s } }
            return nil
        }
    }
}
