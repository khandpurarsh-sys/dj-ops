import SwiftUI

/** Editorial flat-lay feed (Android HomeScreen.kt parity, Shop 240-247): rows of two
 *  flat-lay cards, then one full-width swipeable big card, repeating; jackets and long
 *  coats lead. Whole garment contained on #E0E0E0, square corners, DRESSJET eyebrow,
 *  serif name, price, "+" quick-add with size chips. */
extension Feed {
    static func isOuterwear(_ p: DjProduct) -> Bool {
        let t = (p.type + " " + p.handle).lowercased()
        return ["jacket", "coat", "sherling", "shearling", "trench", "parka"].contains { t.contains($0) }
    }
    static func feedOrdered(_ products: [DjProduct]) -> [DjProduct] {
        products.filter(isOuterwear) + products.filter { !isOuterwear($0) } // stable, catalog order otherwise
    }
    /** 322: with an owner order saved (config/homeOrder) the list is shown exactly as arranged;
     *  jackets/coats only lead by default (no saved order), as before. */
    static func feedChunks(_ products: [DjProduct], ownerOrdered: Bool = false) -> [[DjProduct]] {
        let o = ownerOrdered ? products : feedOrdered(products)
        return stride(from: 0, to: o.count, by: 5).map { Array(o[$0..<min($0 + 5, o.count)]) }
    }
}

enum FlatCache {
    static let cache = NSCache<NSString, UIImage>()
    static func image(_ handle: String) -> UIImage? {
        if let h = cache.object(forKey: handle as NSString) { return h }
        guard let p = FlatLays.path(handle), let src = UIImage(contentsOfFile: p) else { return nil }
        // Decode at display size once: the sources are ~1100x1955.
        let w: CGFloat = 900, s = min(1, w / src.size.width)
        let size = CGSize(width: src.size.width * s, height: src.size.height * s)
        let img = UIGraphicsImageRenderer(size: size).image { _ in src.draw(in: CGRect(origin: .zero, size: size)) }
        cache.setObject(img, forKey: handle as NSString)
        return img
    }
}

private enum CardPage: Hashable { case flat(String), photo(String) }

private let flatGrey = Color(red: 0xE0/255, green: 0xE0/255, blue: 0xE0/255)

private struct PagerCard: View {
    let p: DjProduct
    let ratio: CGFloat
    let flatPad: CGFloat
    let photoWidth: Int
    let dot: CGFloat
    let leadReal: Bool
    let onProduct: (DjProduct) -> Void
    @State private var page = 0

    private var pages: [CardPage] {
        let flat: [CardPage] = FlatLays.path(p.handle) != nil ? [.flat(p.handle)] : []
        let photos = p.images.map { CardPage.photo($0) }
        return leadReal ? photos + flat : flat + photos
    }

    var body: some View {
        let pgs = pages
        if !pgs.isEmpty {
            Color.clear
                .aspectRatio(ratio, contentMode: .fit)
                .overlay {
                    ZStack(alignment: .bottom) {
                        flatGrey
                        TabView(selection: $page) {
                            ForEach(Array(pgs.enumerated()), id: \.offset) { i, pg in
                                Group {
                                    switch pg {
                                    case .flat(let h):
                                        if let img = FlatCache.image(h) {
                                            Image(uiImage: img).resizable().scaledToFit().padding(flatPad)
                                        }
                                    case .photo(let u):
                                        DjImage(url: u, widthPx: photoWidth)
                                    }
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                                .onTapGesture { onProduct(p) }
                                .tag(i)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        HStack(spacing: dot * 0.8) {
                            ForEach(0..<pgs.count, id: \.self) { i in
                                Circle().fill(i == page ? Dj.gold : Color.white.opacity(0.55))
                                    .frame(width: dot, height: dot)
                            }
                        }
                        .padding(.bottom, dot * 2)
                        .allowsHitTesting(false)
                    }
                }
                .clipped()
        }
    }
}

struct EditorialInfo: View {
    let p: DjProduct
    @ObservedObject var bag: Bag
    let onProduct: (DjProduct) -> Void
    @State private var open = false
    @State private var added = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Button { onProduct(p) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow(text: "DressJet", color: Dj.ink3)
                        Text(Feed.displayTitle(p.title))
                            .font(Dj.cormorant(18)).lineSpacing(2).lineLimit(2)
                            .foregroundStyle(Dj.navy).multilineTextAlignment(.leading)
                        Text(Feed.priceLabel(p))
                            .font(Dj.assistant(12.5, weight: .medium)).foregroundStyle(Dj.ink2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(CardPress())
                if !open {
                    Button { open = true; added = false } label: {
                        Text("+").font(.system(size: 26, weight: .light)).foregroundStyle(Dj.navy)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(RailPress())
                }
            }
            if open {
                if added {
                    Text("Added to bag ✓").font(Dj.assistant(12.5, weight: .semibold)).tracking(1)
                        .foregroundStyle(Dj.gold).padding(.vertical, 8)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(p.variants, id: \.id) { v in
                                Button {
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                    bag.add(p, v); added = true
                                } label: {
                                    Text(v.title).font(Dj.assistant(12.5, weight: v.available ? .semibold : .regular)).tracking(1)
                                        .foregroundStyle(v.available ? Dj.navy : Dj.ink3.opacity(0.45))
                                        .padding(.horizontal, 13).padding(.vertical, 6)
                                        .overlay(RoundedRectangle(cornerRadius: 15).stroke(v.available ? Dj.gold : Dj.line, lineWidth: 1))
                                }
                                .buttonStyle(RailPress()).disabled(!v.available)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .padding(.top, 10)
        .animation(DjAnim.enabled ? .spring(response: 0.3, dampingFraction: 0.8) : nil, value: open)
        .animation(DjAnim.enabled ? .spring(response: 0.3, dampingFraction: 0.8) : nil, value: added)
    }
}

struct EditorialChunk: View {
    let chunk: [DjProduct]
    let index: Int
    @ObservedObject var bag: Bag
    let onProduct: (DjProduct) -> Void

    var body: some View {
        let smalls = chunk.count == 5 ? Array(chunk.prefix(4)) : chunk
        VStack(spacing: 0) {
            ForEach(Array(stride(from: 0, to: smalls.count, by: 2)), id: \.self) { s in
                let pair = Array(smalls[s..<min(s + 2, smalls.count)])
                HStack(alignment: .top, spacing: 15) {
                    ForEach(pair) { p in
                        VStack(alignment: .leading, spacing: 0) {
                            PagerCard(p: p, ratio: 0.75, flatPad: 12, photoWidth: 560, dot: 4, leadReal: false, onProduct: onProduct)
                            EditorialInfo(p: p, bag: bag, onProduct: onProduct)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    if pair.count == 1 { Spacer().frame(maxWidth: .infinity) }
                }
                .padding(.horizontal, 15)
                .padding(.bottom, 30)
            }
            if chunk.count == 5 {
                let p = chunk[4]
                VStack(alignment: .leading, spacing: 0) {
                    PagerCard(p: p, ratio: 0.8, flatPad: 18, photoWidth: 1000, dot: 5, leadReal: index % 2 == 1, onProduct: onProduct)
                    EditorialInfo(p: p, bag: bag, onProduct: onProduct).padding(.horizontal, 15)
                }
                .padding(.top, 4).padding(.bottom, 26)
            }
        }
    }
}
