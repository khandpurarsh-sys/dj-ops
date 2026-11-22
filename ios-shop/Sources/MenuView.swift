import SwiftUI
import UIKit

/** Menu sheet (Android MenuSheet.kt parity): frosted white sheet over a dimmed backdrop.
 *  Categories (site nav labels) + Help & Information (the site's own pages; policy pages
 *  render natively, the Logisy returns portal stays a web link). X/scrim dismiss. The
 *  version line settles "did the install take?" on sight. */
struct MenuSheetView: View {
    let onClose: () -> Void
    let onCategory: (String, String) -> Void
    let onPage: (StorePage) -> Void

    private var versionName: String {
        // Android shows 1.0.<run number>; iOS: short version + build number.
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? short : short + "." + build
    }

    var body: some View {
        GeometryReader { geo in
        ZStack(alignment: .bottom) {
            Dj.navy.opacity(0.30)
                .ignoresSafeArea()
                .onTapGesture { onClose() }
            VStack(spacing: 0) {
                Spacer().frame(height: 12)
                RoundedRectangle(cornerRadius: 2).fill(Dj.gold).frame(width: 36, height: 3)
                Spacer().frame(height: 10)
                HStack {
                    SerifTitle(text: "Menu", color: Dj.navy, size: 37)
                    Spacer()
                    Button(action: onClose) {
                        Text("✕").font(.system(size: 17)).foregroundStyle(Dj.navy)
                    }
                }
                if !versionName.isEmpty {
                    Text("DressJet \(versionName)")
                        .font(Dj.assistant(10.5)).tracking(1.8)
                        .foregroundStyle(Dj.navy.opacity(0.75))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }
                ScrollView {
                    VStack(spacing: 0) {
                        AccountSection()
                        SheetLabel("CATEGORIES")
                        SheetRow("All Products") { onCategory(Feed.ALL_HANDLE, "All Products") }
                        ForEach(Feed.MENU_CATEGORIES, id: \.handle) { c in
                            SheetRow(c.label) { onCategory(c.handle, c.label) }
                        }
                        SheetLabel("HELP & INFORMATION")
                        ForEach(Feed.STORE_PAGES, id: \.url) { page in
                            SheetRow(page.title) {
                                if PolicyContent.page(forURL: page.url) != nil {
                                    onPage(page)
                                } else if let url = URL(string: page.url) {
                                    // Interactive returns flow: stays a web link.
                                    UIApplication.shared.open(url)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                // The list viewport ends above the dock (capsule ~58pt + 18pt float + margin), so no row
                // is ever hidden behind it, in any orientation.
                .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 92) }
            }
            .modifier(MenuPanelFrame(landscape: geo.size.width > geo.size.height, height: geo.size.height))
            
        }
        }
        .transition(.opacity)
    }
}

private struct SheetLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(Dj.assistant(9, weight: .semibold)).tracking(2.25)
            .foregroundStyle(Color(red: 0x8A/255, green: 0x75/255, blue: 0x3E/255))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 26).padding(.bottom, 4)
    }
}

private struct SheetRow: View {
    let label: String
    let action: () -> Void
    init(_ label: String, action: @escaping () -> Void) { self.label = label; self.action = action }
    var body: some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack {
                    Text(label)
                        .font(Dj.assistant(16, weight: .medium))
                        .foregroundStyle(Dj.navy)
                    Spacer()
                    Text("→").font(.system(size: 14)).foregroundStyle(Dj.navy)
                }
                .frame(minHeight: 48)
            }
            .buttonStyle(CardPress())
            Rectangle().fill(Dj.navy.opacity(0.14)).frame(height: 1)
        }
    }
}

/** One category's products as a 2-col grid (same cards as the homepage feed). ALL_HANDLE
 *  shows the full connected catalog. 236: scroll position is held by RootView (Back
 *  returns to the product's row); a failed/empty read offers a retry instead of a blank
 *  screen (failures are no longer cached for the session). */
struct CategoryView: View {
    @ObservedObject var repo: Repo
    let handle: String
    let title: String
    let bagCount: Int
    let onBack: () -> Void
    let onBag: () -> Void
    let onProduct: (DjProduct) -> Void
    @Binding var scrollId: String?

    @State private var prods: [DjProduct]? = nil
    @State private var reload = 0

    var body: some View {
        VStack(spacing: 0) {
            Header(dark: false, bagCount: bagCount, onBack: onBack, onBag: onBag)
            if let list = prods, !list.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        RailHeader(title: title)
                            .id("head")
                        let rows = stride(from: 0, to: list.count, by: 2).map { Array(list[$0..<min($0 + 2, list.count)]) }
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            HStack(alignment: .top, spacing: 16) {
                                ForEach(row) { p in
                                    GridCard(product: p, repo: repo, onTap: { onProduct(p) })
                                        .frame(maxWidth: .infinity)
                                }
                                if row.count == 1 { Spacer().frame(maxWidth: .infinity) }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 30)
                            .id("crow-\(row.first?.id ?? 0)")
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.bottom, 40)
                }
                .scrollPosition(id: $scrollId)
                .scrollIndicators(.hidden)
            } else if prods != nil {
                // Empty read (failed loads are not cached): retry instead of a blank grid.
                Spacer()
                Text("Could not load the collection.").font(Dj.assistant(14)).foregroundStyle(Dj.ink2)
                Button(action: { reload += 1 }) {
                    Text("T A P   T O   R E T R Y")
                        .font(Dj.assistant(11.5, weight: .semibold)).tracking(3)
                        .foregroundStyle(Dj.navy).padding(.top, 16)
                }
                Spacer()
            } else {
                Spacer()
                Text("Loading…").font(Dj.assistant(13)).foregroundStyle(Dj.ink3)
                Spacer()
            }
        }
        .background(Color.white.ignoresSafeArea())
        .onAppear { prods = repo.peekCollection(handle) }
        .task(id: reload) {
            await repo.loadCollection(handle)
            prods = repo.peekCollection(handle) ?? []
        }
    }
}


/** Fully glass menu panel: native Liquid Glass on iOS 26+, ultra-thin material before. */
private struct GlassPanel: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .background(Color.white.opacity(0.86), in: RoundedRectangle(cornerRadius: 28))
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
                .background(Color.white.opacity(0.80), in: RoundedRectangle(cornerRadius: 28))
                .overlay(RoundedRectangle(cornerRadius: 28).stroke(Color.white.opacity(0.35), lineWidth: 1))
        }
    }
}


/** Every screen, every orientation: the sheet fills the WHOLE screen. Its backing runs under every
 *  safe area (camera side, rounded corners, home bar); the content stays inside them. */
private struct MenuPanelFrame: ViewModifier {
    let landscape: Bool
    let height: CGFloat
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 26)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.white.opacity(0.97).ignoresSafeArea())
    }
}
