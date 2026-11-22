import SwiftUI

/** v11 white bag: soft cards, thumbs, REMOVE, total, complimentary-shipping line (from the
 *  store's own shipping policy), checkout CTA. Lines carry live website fields only. */
struct BagView: View {
    @ObservedObject var bag: Bag
    let onBack: () -> Void
    let onCheckout: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Header(dark: false, bagCount: bag.count, onBack: onBack)
            HStack {
                SerifTitle(text: "Your Bag", color: Dj.navy, size: 34)
                Spacer()
                if !bag.lines.isEmpty { Eyebrow(text: "\(bag.count) items", color: Dj.ink3) }
            }
            .padding(.horizontal, 26)
            Spacer().frame(height: 14)

            if bag.lines.isEmpty {
                Spacer()
                SerifTitle(text: "Your bag is empty.", color: Dj.ink2, size: 24)
                Spacer().frame(height: 14)
                Eyebrow(text: "Every piece ships across India", color: Dj.ink3)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(bag.lines, id: \.variantId) { line in
                            BagCard(line: line) {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(DjAnim.enabled ? .easeOut(duration: 0.32) : nil) {
                                    bag.remove(line.variantId)
                                }
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .padding(.horizontal, 20)
                }
                VStack(spacing: 0) {
                    HStack {
                        Text("Total").font(Dj.assistant(14)).foregroundStyle(Dj.ink2)
                        Spacer()
                        Text(bag.totalInr).font(Dj.assistant(15.5, weight: .semibold)).foregroundStyle(Dj.navy)
                    }
                    Spacer().frame(height: 6)
                    HStack {
                        Text("Complimentary shipping across India").font(Dj.assistant(11.5)).foregroundStyle(Dj.ink3)
                        Spacer()
                    }
                    Spacer().frame(height: 16)
                    GlassCta(text: "Proceed to Checkout", dark: false, action: onCheckout)
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 18)
            }
        }
        .background(Color.white.ignoresSafeArea())
    }
}

private struct BagCard: View {
    let line: Feed.BagLine
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if !line.image.isEmpty {
                DjImage(url: line.image, widthPx: 300)
                    .frame(width: 72, height: 94)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(Feed.displayTitle(line.title))
                    .font(Dj.cormorant(14.5))
                    .foregroundStyle(Dj.navy)
                    .lineLimit(2)
                if !line.size.isEmpty && line.size != "Default Title" {
                    Spacer().frame(height: 2)
                    Text(line.size).font(Dj.assistant(11.5)).foregroundStyle(Dj.ink3)
                }
                Spacer().frame(height: 6)
                Text("\(Feed.inr(line.price))  ·  Qty \(line.qty)")
                    .font(Dj.assistant(12.5, weight: .semibold)).foregroundStyle(Dj.navy)
            }
            Spacer()
            Button(action: onRemove) {
                Text("R E M O V E")
                    .font(Dj.assistant(9.5, weight: .semibold)).tracking(1.7)
                    .foregroundStyle(Dj.ink3)
            }
        }
        .padding(14)
        .background(LinearGradient(colors: [Color.white.opacity(0.82), Color(red: 0xED/255, green: 0xF3/255, blue: 0xF8/255).opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Dj.navy.opacity(0.085), lineWidth: 1))
    }
}
