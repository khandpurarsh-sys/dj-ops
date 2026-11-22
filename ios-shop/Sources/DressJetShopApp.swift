import SwiftUI

enum AppScreen: Equatable {
    case splash, shop, bag, checkout, search
    case product(DjProduct)
    case category(String, String)
    case policy(StorePage)
}

@main
struct DressJetShopApp: App {
    var body: some Scene {
        WindowGroup {
            if CommandLine.arguments.contains("-dockproof") { DockProofView() }
            else if CommandLine.arguments.contains("-menuproof") { MenuProofView() }
            else { RootView() }
        }
    }
}

struct RootView: View {
    @StateObject private var repo = Repo()
    @StateObject private var bag = Bag()
    @State private var stack: [AppScreen] = [.splash]
    @State private var menuOpen = false
    @State private var dockGlass = true
    @State private var dockMini = false
    @State private var dockVisible = false
    // 236: feed scroll positions live here so a pushed page no longer destroys them -
    // Back returns to the row it left from (Arsh 3:19/3:21 PM).
    @State private var homeScrollId: String? = nil
    @State private var catScrollIds: [String: String] = [:]
    @State private var searchQuery = ""

    var body: some View {
        let top = stack.last ?? .splash
        ZStack(alignment: .bottom) {
            ZStack {
                switch top {
                case .splash:
                    SplashView { push(.shop) }
                        .transition(.opacity)
                case .shop:
                    HomeView(repo: repo, bagCount: bag.count, bag: bag, dockGlass: $dockGlass, dockMini: $dockMini, dockVisible: $dockVisible, scrollId: $homeScrollId,
                             onBag: { push(.bag) },
                             onSearch: { push(.search) },
                             onDiscover: { push(.category(Feed.ALL_HANDLE, "All Products")) }) { push(.product($0)) }
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                case .search:
                    SearchView(repo: repo, bagCount: bag.count, onBack: pop,
                               onBag: { push(.bag) }, onProduct: { push(.product($0)) }, query: $searchQuery)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                case .category(let handle, let title):
                    CategoryView(repo: repo, handle: handle, title: title, bagCount: bag.count,
                                 onBack: pop, onBag: { push(.bag) }, onProduct: { push(.product($0)) },
                                 scrollId: Binding(get: { catScrollIds[handle] }, set: { catScrollIds[handle] = $0 }))
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                case .policy(let page):
                    PolicyView(page: page, onBack: pop)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                case .product(let p):
                    ProductView(product: p, bag: bag, onBack: pop, onBag: { push(.bag) })
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                case .bag:
                    BagView(bag: bag, onBack: pop, onCheckout: { push(.checkout) })
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                case .checkout:
                    CheckoutView(bag: bag, onBack: pop)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                }
            }
            .animation(DjAnim.enabled ? .easeOut(duration: 0.32) : nil, value: top)

            // Dock floats over the home stack (home/search/category/policy/product), like
            // Android: hidden on splash/bag/checkout. Cream over the hero, solid navy the
            // instant white content touches it.
            if top == .shop {
                DockOverlay(dock: Dock(current: menuOpen ? "menu" : "home",
                     bagCount: bag.count,
                     dark: !menuOpen && dockGlass,
                     mini: dockMini && !menuOpen,
                     onHome: { menuOpen = false; popToHome() },
                     onMenu: { menuOpen.toggle() },
                     onBag: { menuOpen = false; push(.bag) }))
                    .opacity(dockVisible || menuOpen ? 1 : 0)
                    .offset(y: dockVisible || menuOpen ? 0 : 26)
                    .allowsHitTesting(dockVisible || menuOpen)
                    .animation(DjAnim.enabled ? .smooth(duration: 0.5) : nil, value: dockVisible)
                    .zIndex(3)
            }

            if menuOpen {
                MenuSheetView(onClose: { menuOpen = false },
                              onCategory: { h, t in menuOpen = false; push(.category(h, t)) },
                              onPage: { p in menuOpen = false; push(.policy(p)) })
                    .zIndex(2)
            }
        }
        .animation(DjAnim.enabled ? .spring(response: 0.38, dampingFraction: 0.82) : nil, value: menuOpen)
        .background(Color.white.ignoresSafeArea()) // 224: no system-colour edge during slides
        .onAppear { repo.refresh(); Account.shared.attach(bag) }
    }

    private func push(_ s: AppScreen) { stack.append(s) }
    private func pop() {
        if menuOpen { menuOpen = false; return } // back closes the sheet, never pops
        if stack.last == .shop { return } // Home is the root: back there does nothing (it used to fall back to the splash)
        if stack.count > 1 { stack.removeLast() }
    }
    private func popToHome() {
        if let ix = stack.lastIndex(of: .shop) { stack = Array(stack[...ix]) }
    }
}
