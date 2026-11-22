import SwiftUI
import ImageIO

/** Shared chrome: wordmark header, glass CTA, serif title, eyebrow, async image. */

struct Wordmark: View {
    let color: Color
    var body: some View {
        Text("DRESSJET")
            .font(Dj.cinzel(15))
            .tracking(5.7)
            .foregroundStyle(color)
    }
}

struct Eyebrow: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text.uppercased())
            .font(Dj.assistant(10.5, weight: .semibold))
            .tracking(3.6)
            .foregroundStyle(color)
    }
}

struct SerifTitle: View {
    let text: String
    let color: Color
    let size: CGFloat
    var italic = true
    var body: some View {
        Text(text)
            .font(Dj.cormorant(size, italic: italic))
            .foregroundStyle(color)
    }
}

/** Image cache + loader (Android Coil parity): Shopify CDN width param (never the full-size
 *  original), ImageIO downsample, decoded-image NSCache, in-flight dedupe. AsyncImage kept
 *  no decoded cache, so scrolling back re-downloaded full-size photos (grey/missing tiles). */
final class DjImageLoader {
    static let shared = DjImageLoader()
    private let cache = NSCache<NSString, UIImage>()
    private let session: URLSession
    private var inflight: [String: Task<UIImage?, Never>] = [:]
    private let lock = NSLock()
    init() {
        cache.totalCostLimit = 120 * 1024 * 1024
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = URLCache(memoryCapacity: 30 * 1024 * 1024, diskCapacity: 300 * 1024 * 1024)
        cfg.requestCachePolicy = .returnCacheDataElseLoad
        cfg.httpMaximumConnectionsPerHost = 6
        session = URLSession(configuration: cfg)
    }
    static func sized(_ url: String, _ w: Int) -> String {
        guard w > 0, url.hasPrefix("https://cdn.shopify.com/") else { return url }
        return url + (url.contains("?") ? "&" : "?") + "width=\(w)"
    }
    func cached(_ url: String, _ w: Int) -> UIImage? { cache.object(forKey: Self.sized(url, w) as NSString) }
    func load(_ url: String, _ w: Int) async -> UIImage? {
        let key = Self.sized(url, w)
        if let hit = cache.object(forKey: key as NSString) { return hit }
        lock.lock()
        let task: Task<UIImage?, Never>
        if let t = inflight[key] { task = t } else {
            task = Task.detached(priority: .userInitiated) { [session, cache] in
                guard let u = URL(string: key),
                      let (data, _) = try? await session.data(from: u) else { return nil }
                let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                             kCGImageSourceCreateThumbnailWithTransform: true,
                                             kCGImageSourceShouldCacheImmediately: true,
                                             kCGImageSourceThumbnailMaxPixelSize: max(w, 64)]
                guard let src = CGImageSourceCreateWithData(data as CFData, nil),
                      let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
                let img = UIImage(cgImage: cg)
                cache.setObject(img, forKey: key as NSString, cost: cg.width * cg.height * 4)
                return img
            }
            inflight[key] = task
        }
        lock.unlock()
        let r = await task.value
        lock.lock(); inflight[key] = nil; lock.unlock()
        return r
    }
}

struct DjImage: View {
    let url: String
    var widthPx: Int = 900
    @State private var img: UIImage? = nil
    var body: some View {
        ZStack {
            Color(red: 0xE6/255, green: 0xE3/255, blue: 0xDC/255) // 224: visible warm placeholder (the old #EEF1F4 read as blank white)
            if let img { Image(uiImage: img).resizable().scaledToFill().transition(.identity) }
        }
        .clipped()
        .onAppear { if img == nil { img = DjImageLoader.shared.cached(url, widthPx) } }
        .task(id: url) {
            if let hit = DjImageLoader.shared.cached(url, widthPx) { img = hit; return }
            var r = await DjImageLoader.shared.load(url, widthPx)
            if r == nil && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                r = await DjImageLoader.shared.load(url, widthPx)
            }
            if let r { img = r } else { DjDiag.log("img " + String(url.split(separator: "/").last?.prefix(28) ?? "")) }
        }
    }
}

struct BagIcon: View {
    let count: Int
    let tint: Color
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "bag")
                .font(.system(size: 17, weight: .light))
                .foregroundStyle(tint)
            if count > 0 {
                Text("\(count)")
                    .font(Dj.assistant(9.5, weight: .semibold))
                    .foregroundStyle(Dj.navy)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Dj.gold, in: Capsule())
                    .offset(x: 8, y: -8)
            }
        }
        .frame(width: 30, height: 30)
    }
}

/** Glass CTA (54pt, radius 28). Dark variant for navy screens, light for white screens. */
struct GlassCta: View {
    let text: String
    let dark: Bool
    let action: () -> Void

    private struct PressStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed && DjAnim.enabled ? 0.97 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
        }
    }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Text(text.uppercased())
                .font(Dj.assistant(11.5, weight: .semibold))
                .tracking(3)
                .foregroundStyle(dark ? Dj.cream : Dj.navy)
                .frame(maxWidth: .infinity).frame(height: 54)
                .background(
                    dark ? AnyShapeStyle(Dj.cream.opacity(0.10))
                         : AnyShapeStyle(LinearGradient(colors: [Color.white.opacity(0.60), Color(red: 0xE2/255, green: 0xED/255, blue: 0xF5/255).opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)),
                    in: Capsule())
                .overlay(Capsule().stroke(dark ? Dj.cream.opacity(0.30) : Dj.gold.opacity(0.55), lineWidth: 1))
        }
        .buttonStyle(PressStyle())
    }
}

/** Header row (64pt under the safe area): back chevron slot, wordmark, bag. */
struct Header: View {
    let dark: Bool
    let bagCount: Int
    var onBack: (() -> Void)? = nil
    var onBag: () -> Void = {}
    var body: some View {
        let ink = dark ? Dj.cream : Dj.navy
        HStack {
            Group {
                if let onBack {
                    Button(action: onBack) {
                        Text("‹").font(.system(size: 24)).foregroundStyle(ink)
                            .frame(width: 44, height: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                }
            }.frame(width: 44, alignment: .leading)
            Spacer()
            Wordmark(color: ink)
            Spacer()
            Button(action: onBag) {
                BagIcon(count: bagCount, tint: ink)
                    .frame(width: 44, height: 44, alignment: .trailing)
                    .contentShape(Rectangle())
            }
        }
        .frame(height: 64)
        .padding(.horizontal, 20)
    }
}

/** Frosted glass pill (liquid glass: the blur shows what is beneath it). Wraps one
 *  tappable row of content; used by the home search header and the hero "Shop Now". */
struct FrostedPill<Content: View>: View {
    let dark: Bool
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    var body: some View {
        Button(action: action) {
            content()
        }
        .buttonStyle(.plain)
        // 220-ios: the plain .ultraThinMaterial followed the PHONE's dark mode and read as
        // opaque grey over white content (his 9:36 PM video). Force the light material and
        // add the translucent white tint the Android glass uses.
        .background {
            ZStack {
                Color.white.opacity(dark ? 0.22 : 0.62)
            }
            .clipShape(Capsule())
            .environment(\.colorScheme, .light)
        }
        .overlay(Capsule().stroke(dark ? Color.white.opacity(0.55) : Dj.navy.opacity(0.10), lineWidth: 1))
    }
}

/** 220-ios shared bits. */
private struct DjFeedScrollingKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var djFeedScrolling: Bool {
        get { self[DjFeedScrollingKey.self] }
        set { self[DjFeedScrollingKey.self] = newValue }
    }
}
enum DjLaunch { static let t0 = Date() }

/** On-device diagnostics (like Android's DjDiag): one line, shown bottom-left on Home
 *  until Arsh says remove. */
@MainActor final class DjDiagModel: ObservableObject { @Published var line = "" }
enum DjDiag {
    @MainActor static let model = DjDiagModel()
    @MainActor static func log(_ s: String) { model.line = String(s.prefix(90)) }
}
struct DjDiagStrip: View {
    @ObservedObject private var m = DjDiag.model
    var body: some View {
        if m.line.isEmpty { EmptyView() } else {
            Text(m.line).font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color(red: 1, green: 0.77, blue: 0.69))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color(red: 0.04, green: 0.13, blue: 0.21).opacity(0.7))
        }
    }
}

/** Bottom dock (Home / Menu / Bag, Android Frost.kt Dock parity): NO background at all -
 *  just the words - while it floats; solid navy pill with a gold hairline the instant
 *  white content touches it. Ink follows the backdrop: cream over the hero video, navy
 *  over light content. */
struct DockFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue()) { $1 } }
}

struct Dock: View {
    let current: String
    let bagCount: Int
    /** true while the dock is over the hero video (cream ink); false over white content (navy ink). */
    let dark: Bool
    var mini: Bool = false
    /** pixel-proof fixture only: hides the Menu word so its own pixels can be diffed out. */
    var menuHidden: Bool = false
    let onHome: () -> Void
    let onMenu: () -> Void
    let onBag: () -> Void

    /** Every slot is the same width, so Menu is the exact centre of the capsule (and the
     *  capsule is centred by its parent) whether or not Home and Bag are showing. */
    static let slotW: CGFloat = 96

    private func probe(_ key: String) -> some View {
        GeometryReader { g in Color.clear.preference(key: DockFramesKey.self, value: [key: g.frame(in: .global)]) }
    }

    var body: some View {
        let ink = dark ? Dj.cream : Dj.navy
        let side: CGFloat = mini ? 0 : 1
        let row = HStack(spacing: 0) {
            DockItem(label: "Home", active: current == "home", ink: ink, badge: 0, action: onHome)
                .frame(width: Dock.slotW).fixedSize()
                .frame(width: Dock.slotW * side).opacity(Double(side)).clipped()
                .allowsHitTesting(!mini)
            DockItem(label: "Menu", active: current == "menu", ink: ink, badge: 0, action: onMenu)
                .opacity(menuHidden ? 0 : 1)
                .frame(width: Dock.slotW)
                .background(probe("menu"))
            DockItem(label: "Bag", active: current == "bag", ink: ink, badge: bagCount, action: onBag)
                .frame(width: Dock.slotW).fixedSize()
                .frame(width: Dock.slotW * side).opacity(Double(side)).clipped()
                .allowsHitTesting(!mini)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .animation(DjAnim.enabled ? .smooth(duration: 0.55) : nil, value: mini)
        .animation(.easeInOut(duration: 0.25), value: dark)
        // Neutral backing under the glass so the words read over any video or white page.
        let backing = Capsule().fill(dark ? Color.black.opacity(0.30) : Color.white.opacity(0.55))
        Group {
            if #available(iOS 26.0, *) {
                row.background(backing).glassEffect(.regular, in: Capsule())
            } else {
                row.background(backing).background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1))
            }
        }
        .background(probe("capsule"))
    }
}

private struct DockItem: View {
    let label: String
    let active: Bool
    let ink: Color
    var pressInk: Color? = nil
    var activeInk: Color? = nil
    let badge: Int
    let action: () -> Void

    private struct Press: ButtonStyle {
        let tint: Color?
        let base: Color
        let on: Bool
        let activeTint: Color?
        func makeBody(configuration: Configuration) -> some View {
            configuration.label.environment(\.djDockInk,
                configuration.isPressed ? (tint ?? base) : (on ? (activeTint ?? base) : base))
        }
    }

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            DockItemLabel(label: label, active: active, ink: ink, badge: badge)
        }
        .buttonStyle(Press(tint: pressInk, base: ink, on: active, activeTint: activeInk))
    }
}

private struct DjDockInkKey: EnvironmentKey { static let defaultValue: Color = .clear }
extension EnvironmentValues {
    var djDockInk: Color { get { self[DjDockInkKey.self] } set { self[DjDockInkKey.self] = newValue } }
}

private struct DockItemLabel: View {
    let label: String
    let active: Bool
    let ink: Color
    let badge: Int
    @Environment(\.djDockInk) private var shown
    var body: some View {
        let ink = shown == .clear ? self.ink : shown
        VStack(spacing: 3) {
            ZStack(alignment: .topTrailing) {
                Text(label.uppercased())
                    .font(Dj.assistant(13, weight: .semibold)).tracking(1.8)
                    .padding(.leading, 1.8)
                    .foregroundStyle(ink.opacity(active ? 1 : 0.92))
                    .shadow(color: (ink == Dj.cream ? Color.black.opacity(0.55) : Color.clear), radius: 2, x: 0, y: 1)
                if badge > 0 {
                    Text("\(badge)")
                        .font(Dj.assistant(8.5, weight: .semibold))
                        .foregroundStyle(Dj.navy)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Dj.gold, in: Capsule())
                        .offset(x: 12, y: -5)
                }
            }
            Circle().fill((shown != .clear && shown != self.ink ? ink : Dj.gold).opacity(active ? 1 : 0)).frame(width: 4, height: 4)
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}


/** Right-edge liquid-glass rail (replaces the bottom dock for the Duo layout): vertical
 *  Home / Search / Menu / Bag, 44pt targets, native Liquid Glass on iOS 26+, ultra-thin
 *  material before that. Sits in the trailing safe area; never over product/bag CTAs
 *  because it only shows on Home. */
struct SideRail: View {
    let menuOpen: Bool
    let bagCount: Int
    let onHome: () -> Void
    let onSearch: () -> Void
    let onMenu: () -> Void
    let onBag: () -> Void

    private let gold = Color(red: 0xD3/255, green: 0xC6/255, blue: 0xA2/255)
    private let dim = Color(red: 0xA8/255, green: 0x9A/255, blue: 0x76/255)

    private func item(_ symbol: String, _ label: String, active: Bool = false, badge: Int = 0, _ action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: symbol).font(.system(size: 17, weight: .medium))
                    .foregroundStyle(active ? gold : Color.white)
                    .shadow(color: .black.opacity(0.55), radius: 2, x: 0, y: 1)
                    .frame(width: 40, height: 40)
                if badge > 0 {
                    Text("\(badge)").font(Dj.assistant(9.5, weight: .semibold)).foregroundStyle(Dj.navy)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Dj.gold, in: Capsule()).offset(x: -2, y: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RailPress())
        .accessibilityLabel(label)
    }

    var body: some View {
        let stack = VStack(spacing: 0) {
            item("house", "Home", active: !menuOpen, onHome)
            item("magnifyingglass", "Search", onSearch)
            item("line.3.horizontal", "Menu", active: menuOpen, onMenu)
            item("bag", "Bag", badge: bagCount, onBag)
        }
        .padding(.vertical, 6).padding(.horizontal, 3)
        if #available(iOS 26.0, *) {
            stack.glassEffect(.regular, in: Capsule())
        } else {
            stack.background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1))
        }
    }
}


/** Reactive press: quick spring scale + dim, like the website's tap feedback. */
struct RailPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && DjAnim.enabled ? 0.82 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/** Card press feedback for the feed. */
struct CardPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && DjAnim.enabled ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}


/** Full-width host for the dock: ignores the horizontal safe area (the Duo's cover screen has
 *  a much larger trailing inset than leading) so the capsule is centred on the PHYSICAL screen,
 *  not on the safe-area box. Bottom still respects the home-indicator inset. */
struct DockOverlay: View {
    let dock: Dock
    var body: some View {
        GeometryReader { _ in
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                dock
                Spacer(minLength: 0)
            }
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .ignoresSafeArea(.container, edges: .horizontal)
    }
}

/** Launch-argument fixture (-dockproof light|dark [mini] [nodock] [nomenu]) used only by the CI
 *  pixel proof: flat background + the real DockOverlay inside an artificial 34pt trailing inset. */
struct DockProofView: View {
    var body: some View {
        let a = CommandLine.arguments
        let dark = a.contains("dark"), mini = a.contains("mini")
        ZStack(alignment: .bottom) {
            (dark ? Color(white: 0.35) : Color.white).ignoresSafeArea()
            if !a.contains("nodock") {
                DockOverlay(dock: Dock(current: "home", bagCount: 0, dark: dark, mini: mini,
                                       menuHidden: a.contains("nomenu"), onHome: {}, onMenu: {}, onBag: {}))
            }
        }
        .safeAreaInset(edge: .trailing, spacing: 0) { Color.clear.frame(width: 34) }
    }
}


/** CI fixture (-menuproof [landR|landL] [nodock]): real Menu sheet + dock over a loud red page so any
 *  uncovered strip is obvious in the screenshot; rotates the scene to the requested orientation. */
struct MenuProofView: View {
    var body: some View {
        let a = CommandLine.arguments
        ZStack(alignment: .bottom) {
            Color(red: 0.80, green: 0.22, blue: 0.17).ignoresSafeArea()
            MenuSheetView(onClose: {}, onCategory: { _, _ in }, onPage: { _ in })
            if !a.contains("nodock") {
                DockOverlay(dock: Dock(current: "menu", bagCount: 0, dark: false, onHome: {}, onMenu: {}, onBag: {}))
            }
        }
        // "inset": simulate the foldable cover screen's lopsided safe area (big trailing, some top/leading).
        .safeAreaInset(edge: .trailing, spacing: 0) { Color.clear.frame(width: a.contains("inset") ? 100 : 0) }
        .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: a.contains("inset") ? 40 : 0) }
        .safeAreaInset(edge: .leading, spacing: 0) { Color.clear.frame(width: a.contains("inset") ? 24 : 0) }
        .onAppear {
            let m: UIInterfaceOrientationMask = a.contains("landR") ? .landscapeRight : (a.contains("landL") ? .landscapeLeft : .portrait)
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    scene.requestGeometryUpdate(.iOS(interfaceOrientations: m)) { _ in }
                }
            }
        }
    }
}
