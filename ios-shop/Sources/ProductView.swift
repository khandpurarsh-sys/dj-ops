import SwiftUI

/** Product page with the native details sheet (Android 214 parity): full-bleed dark photo
 *  pager, navy veil, name + selling price only, real sizes from variant data, glass "Add to
 *  Bag", pager parallax. The WHOLE surface drags the details sheet (a swipe starting on the
 *  image included); the sheet follows the finger and settles to the nearest end, and a
 *  short FLICK opens it (settle uses the predicted end offset, the SwiftUI fling signal).
 *  Parked fully below the screen it is hidden from hit-testing and accessibility. Sheet
 *  content mirrors the website PDP: gold dispatch card, Description, then the site's own
 *  accordions with text quoted verbatim (Feed). Back closes the sheet, never pops, while
 *  the sheet is open. */
struct ProductView: View {
    let product: DjProduct
    @ObservedObject var bag: Bag
    let onBack: () -> Void
    let onBag: () -> Void

    @State private var page = 0
    @State private var pagePos: Int? = 0
    private static var safe: UIEdgeInsets {
        (UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.keyWindow?.safeAreaInsets) ?? .zero
    }
    /** Android parity: the product's own site video leads the pager (website media only). */
    @State private var video: DjVideo? = nil
    @State private var zoomUrl: String? = nil
    private var offset: Int { video == nil ? 0 : 1 }
    private var totalPages: Int { product.images.count + offset }
    @State private var selected = 0
    @State private var fly = false
    @State private var sheetPx: CGFloat = 1 // parked below; 0 = open
    @State private var screenH: CGFloat = 1

    private var sheetOpen: Bool { sheetPx < screenH * 0.6 }

    var body: some View {
        let variants = product.variants
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Dj.navyDeep.ignoresSafeArea()
                // The details-sheet drag covers the content only; the header sits ABOVE it and outside
                // it, so a back/bag tap can never be read as the start of a sheet drag.
                ZStack(alignment: .top) {
                    pager(variants: variants, size: geo.size)
                    veil
                    bottomContent(variants: variants)
                    if fly {
                        Circle().fill(Dj.gold).frame(width: 14, height: 14)
                            .offset(y: -320)
                            .opacity(0)
                            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                    }
                    sheet(variants: variants, size: geo.size)
                }
                .contentShape(Rectangle())
                .simultaneousGesture(sheetDrag)
                header
            }
            .fullScreenCover(item: Binding(get: { zoomUrl.map { ZoomItem(url: $0) } }, set: { zoomUrl = $0?.url })) { z in
                ZoomViewer(url: z.url) { zoomUrl = nil }
            }
            .task(id: product.handle) {
                if let d = try? await URLSession.shared.data(from: Feed.productJsURL(product.handle)).0,
                   let v = Feed.parseProductVideo(d) {
                    video = v
                    // The video inserts pager page 0; shift right so the photo the user
                    // is already looking at (and the counter) stays stable.
                    pagePos = (pagePos ?? 0) + 1
                }
            }
            .onAppear {
                screenH = geo.size.height
                if sheetPx <= 1 || sheetPx > geo.size.height { sheetPx = geo.size.height }
                if !variants.indices.contains(selected) || !variants[selected].available {
                    selected = variants.firstIndex(where: { $0.available }) ?? 0
                }
            }
        }
        .ignoresSafeArea() // edge to edge: sizes below come from the FULL screen
    }

    // MARK: pager + veil + header + bottom content (the approved Nov 4 design)

    /** 222b: a SwiftUI paging ScrollView instead of TabView(.page) - the TabView page style
     *  kept its own safe-area inset (the navy band under the status bar) and its UIKit pan
     *  recogniser fought the details-sheet drag. Pages are sized from the FULL screen. */
    private func pager(variants: [DjVariant], size: CGSize) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                if let video {
                    PdpVideoView(video: video, active: page == 0)
                        .frame(width: size.width, height: size.height).clipped().id(0)
                }
                ForEach(Array(product.images.enumerated()), id: \.offset) { i, src in
                    let ix = i + offset
                    DjImage(url: src, widthPx: 1200)
                        .frame(width: size.width, height: size.height).clipped()
                        .contentShape(Rectangle())
                        .onTapGesture { zoomUrl = src }
                        .id(ix)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $pagePos)
        .scrollIndicators(.hidden)
        .frame(width: size.width, height: size.height)
        .onChange(of: pagePos) { _, now in page = now ?? 0 }
    }

    private var veil: some View {
        VStack { Spacer() }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(stops: [
                    .init(color: .clear, location: 0.45),
                    .init(color: Dj.navy.opacity(0.30), location: 0.66),
                    .init(color: Dj.navyDeep.opacity(0.94), location: 1.0)],
                    startPoint: .top, endPoint: .bottom)
                    .frame(height: 520),
                alignment: .bottom)
            .allowsHitTesting(false)
    }

    private var header: some View {
        HStack {
            Button {
                if sheetOpen { closeSheet() } else { onBack() } // sheet open: back closes it
            } label: {
                Text("‹").font(.system(size: 22)).foregroundStyle(Dj.cream)
                    .frame(width: 38, height: 38)
                    .background(Color.black.opacity(0.28), in: Circle())
                    .overlay(Circle().stroke(Dj.cream.opacity(0.25), lineWidth: 1))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            Spacer()
            Button(action: onBag) {
                BagIcon(count: bag.count, tint: Dj.cream)
                    .frame(width: 38, height: 38)
                    .background(Color.black.opacity(0.28), in: Circle())
                    .overlay(Circle().stroke(Dj.cream.opacity(0.25), lineWidth: 1))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8 + Self.safe.top)
    }

    private func bottomContent(variants: [DjVariant]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            HStack {
                Spacer()
                Text("\(page + 1) / \(totalPages)")
                    .font(Dj.assistant(11)).tracking(2).foregroundStyle(Dj.cream.opacity(0.6))
            }
            Spacer().frame(height: 8)
            // DETAILS handle - tap opens the sheet, a swipe up anywhere does too
            HStack(spacing: 8) {
                Rectangle().fill(Dj.gold).frame(width: 18, height: 1)
                Text("D E T A I L S")
                    .font(Dj.assistant(10.5, weight: .semibold)).tracking(3.6)
                    .foregroundStyle(Dj.gold2)
            }
            .contentShape(Rectangle())
            .onTapGesture { openSheet() }
            Spacer().frame(height: 8)
            Text(Feed.displayTitle(product.title))
                .font(Dj.cormorant(36, italic: true))
                .foregroundStyle(Dj.cream)
            Spacer().frame(height: 10)
            Text(Feed.inr(variants[selected].price))
                .font(Dj.assistant(15, weight: .semibold)).tracking(1.5)
                .foregroundStyle(Dj.gold2)
            if variants.count > 1 {
                Spacer().frame(height: 22)
                HStack(spacing: 28) {
                    ForEach(Array(variants.enumerated()), id: \.element.id) { ix, v in
                        VStack(spacing: 5) {
                            Text(v.title)
                                .font(Dj.assistant(13.5, weight: ix == selected ? .semibold : .regular))
                                .tracking(1)
                                .foregroundStyle(ix == selected ? Dj.cream : Dj.cream.opacity(0.5))
                            Rectangle()
                                .fill(ix == selected ? Dj.gold : .clear)
                                .frame(width: ix == selected ? 18 : 6, height: 1.5)
                        }
                        .onTapGesture {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(DjAnim.enabled ? .easeOut(duration: 0.2) : nil) { selected = ix }
                        }
                    }
                }
            }
            Spacer().frame(height: 26)
            if variants[selected].available {
                GlassCta(text: "Add to Bag", dark: true) {
                    bag.add(product, variants[selected])
                    if DjAnim.enabled {
                        withAnimation(.easeOut(duration: 0.6)) { fly = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { fly = false }
                    }
                }
            } else {
                GlassCta(text: "Sold Out", dark: true) { }
            }
            Spacer().frame(height: 30 + Self.safe.bottom)
        }
        .padding(.horizontal, 26)
    }

    // MARK: details sheet

    private var sheetDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { v in
                // vertical intent only: horizontal pager swipes must never move the sheet
                // sheet fully open: its own ScrollView owns vertical drags, except from the title strip
                if sheetPx < 2 && v.startLocation.y > Self.safe.top + 90 { return }
                if !dragVertical {
                    if abs(v.translation.height) > abs(v.translation.width) { dragVertical = true } else { return }
                }
                let next = sheetPx + v.translation.height - lastDrag
                lastDrag = v.translation.height
                sheetPx = min(max(next, 0), screenH)
            }
            .onEnded { v in
                lastDrag = 0
                defer { dragVertical = false }
                if !dragVertical { return }
                // Flick-aware settle: the predicted end carries the fling (212: a short
                // fast swipe must open it even when the finger barely moved).
                let predicted = sheetPx + (v.predictedEndTranslation.height - v.translation.height)
                let open = predicted < screenH * 0.5
                withAnimation(.easeOut(duration: 0.3)) { sheetPx = open ? 0 : screenH }
            }
    }
    @State private var lastDrag: CGFloat = 0
    @State private var dragVertical = false

    private func openSheet() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(DjAnim.enabled ? .easeOut(duration: 0.3) : nil) { sheetPx = 0 }
    }
    private func closeSheet() {
        withAnimation(DjAnim.enabled ? .easeOut(duration: 0.26) : nil) { sheetPx = screenH }
    }

    private func sheet(variants: [DjVariant], size: CGSize) -> some View {
        let parked = sheetPx >= screenH - 2
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 14 + Self.safe.top)
                HStack(alignment: .center) {
                    SerifTitle(text: Feed.displayTitle(product.title), color: Dj.navy, size: 30)
                    Spacer()
                    Button { closeSheet() } label: {
                        Text("✕").font(.system(size: 17)).foregroundStyle(Dj.navy)
                    }
                }
                Spacer().frame(height: 6)
                Rectangle().fill(Dj.gold).frame(width: 34, height: 2)
                Spacer().frame(height: 10)
                Text(Feed.inr(variants[selected].price))
                    .font(Dj.assistant(15, weight: .semibold)).tracking(1.5)
                    .foregroundStyle(Dj.navy)
                Spacer().frame(height: 14)
                // Dispatch trust card - mirrors the site PDP's gold card verbatim
                HStack(alignment: .center, spacing: 10) {
                    Text("⚡").font(.system(size: 16))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dispatch within 24 Hours")
                            .font(Dj.assistant(13.5, weight: .semibold)).foregroundStyle(Dj.navy)
                        Text("Sunday orders ship the next working day")
                            .font(Dj.assistant(11.5)).foregroundStyle(Dj.ink2)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Dj.cream, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Dj.gold.opacity(0.55), lineWidth: 1))
                if !product.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    DetailHead("Description")
                    DetailBody(product.description)
                }
                Spacer().frame(height: 10)
                SheetAccordion(title: "Shipping and Returns") {
                    ForEach(Feed.SHIPPING_LINES, id: \.self) { DetailBody($0) }
                }
                SheetAccordion(title: "Return Policies") {
                    ForEach(Feed.REFUND_LINES, id: \.self) { DetailBody("•  \($0)") }
                }
                SheetAccordion(title: "Need Help? We're Here for You") {
                    ForEach(Feed.SUPPORT_LINES, id: \.self) { DetailBody($0) }
                }
                Rectangle().fill(Dj.gold.opacity(0.35)).frame(height: 1)
                Spacer().frame(height: 46 + Self.safe.bottom)
            }
            .padding(.horizontal, 28)
        }
        .frame(width: size.width, height: size.height)
        .background(Color.white)
        .offset(y: sheetPx)
        .accessibilityHidden(parked)
        .allowsHitTesting(!parked)
    }
}

private struct DetailHead: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(Dj.cormorant(20, italic: true))
            .foregroundStyle(Dj.navy)
            .padding(.top, 18)
    }
}

private struct DetailBody: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(Dj.assistant(13.5)).lineSpacing(6)
            .foregroundStyle(Dj.ink2)
            .padding(.top, 6)
    }
}

/** Gold-underlined disclosure row; content expands below it (the site's PDP accordions). */
private struct SheetAccordion<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @State private var open = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(DjAnim.enabled ? .easeOut(duration: 0.25) : nil) { open.toggle() }
            } label: {
                HStack {
                    Text(title)
                        .font(Dj.assistant(13, weight: .semibold)).tracking(1.2)
                        .foregroundStyle(Dj.navy)
                    Spacer()
                    Text(open ? "−" : "+")
                        .font(Dj.assistant(15, weight: .medium))
                        .foregroundStyle(Dj.gold)
                }
                .padding(.vertical, 14)
            }
            if open { content().padding(.bottom, 12) }
            Rectangle().fill(Dj.navy.opacity(0.10)).frame(height: 1)
        }
    }
}

private struct ZoomItem: Identifiable { let url: String; var id: String { url } }

/** Tap-to-zoom viewer (Android zoom viewer parity): pinch to zoom, double-tap toggles, tap
 *  the X to close. */
private struct ZoomViewer: View {
    let url: String
    let onClose: () -> Void
    @State private var scale: CGFloat = 1
    @State private var base: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panBase: CGSize = .zero
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                Dj.navyDeep.ignoresSafeArea()
                DjImage(url: url, widthPx: 1600)
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(pan)
                    .gesture(MagnificationGesture()
                        .onChanged { scale = max(1, min(4, base * $0)) }
                        .onEnded { _ in
                            base = scale
                            if scale <= 1 { pan = .zero; panBase = .zero }
                        })
                    // Drag to pan while zoomed (Android parity), clamped to the zoomed
                    // photo's own overflow so it can never be lost off-screen.
                    .simultaneousGesture(DragGesture()
                        .onChanged { v in
                            guard scale > 1 else { return }
                            let mx = (scale - 1) * geo.size.width / 2
                            let my = (scale - 1) * geo.size.height / 2
                            pan = CGSize(width: min(max(panBase.width + v.translation.width, -mx), mx),
                                         height: min(max(panBase.height + v.translation.height, -my), my))
                        }
                        .onEnded { _ in panBase = pan })
                    .onTapGesture(count: 2) { withAnimation(.easeOut(duration: 0.2)) { scale = scale > 1 ? 1 : 2.5; base = scale; pan = .zero; panBase = .zero } }
                Button(action: onClose) {
                    Text("✕").font(.system(size: 17)).foregroundStyle(Dj.cream)
                        .frame(width: 44, height: 44)
                }
                .padding(.top, 8).padding(.trailing, 12)
            }
        }
    }
}

/** Product video page: muted loop, poster until the first frame. */
private struct PdpVideoView: View {
    let video: DjVideo
    let active: Bool
    @StateObject private var holder: LoopPlayer
    init(video: DjVideo, active: Bool) {
        self.video = video; self.active = active
        _holder = StateObject(wrappedValue: LoopPlayer(url: video.url, active: active, budgeted: false))
    }
    var body: some View {
        ZStack {
            if let p = holder.player { PlayerLayerView(player: p) }
            if !holder.ready, let poster = video.poster { DjImage(url: poster, widthPx: 1200) }
        }
        .onChange(of: active) { _, now in holder.setActive(now) }
        .onDisappear { holder.release() }
    }
}
