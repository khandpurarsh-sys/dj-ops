import SwiftUI

/** Splash: the real DressJet logo, handwritten on by a pen (hanger, then the wordmark), flat navy and thin
 *  champagne gold, one glint. Drawn natively every frame from vector outlines (splash_vec.json): no video,
 *  no bitmap, so there is no static first frame, and TimelineView follows the display refresh rate
 *  (ProMotion enabled by CADisableMinimumFrameDurationOnPhone). The launch screen is the same navy.
 *  Port of the v4 preview. ENTER fades in as the write-on ends. */
struct SplashView: View {
    let onEnter: () -> Void
    @State private var shown = false
    @State private var start = Date()
    @State private var finished = false
    private let vec = SplashVec.shared

    static let speed: Float = 1.5   // time-based: same drawing, played 1.5x faster
    static let bg = Color(red: 0x10/255, green: 0x2A/255, blue: 0x4A/255)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Self.bg.ignoresSafeArea()
                if let v = vec {
                    TimelineView(.animation(minimumInterval: nil, paused: finished || !DjAnim.enabled)) { tl in
                        let t = DjAnim.enabled ? min(Float(tl.date.timeIntervalSince(start)) * Self.speed, v.dur) : v.dur
                        Canvas(rendersAsynchronously: false) { ctx, size in v.draw(&ctx, size, t) }
                    }
                    .ignoresSafeArea()
                }
                VStack(spacing: 18) {
                    Spacer()
                    Text("N E W   A R R I V A L S")
                        .font(Dj.assistant(10, weight: .semibold))
                        .foregroundStyle(Dj.gold2.opacity(0.65))
                    Button(action: onEnter) {
                        Text("E N T E R")
                            .font(Dj.assistant(11.5, weight: .semibold))
                            .foregroundStyle(Dj.cream)
                            .padding(.horizontal, 44).padding(.vertical, 15)
                            .background(Dj.cream.opacity(0.10), in: Capsule())
                            .overlay(Capsule().stroke(Dj.cream.opacity(0.30), lineWidth: 1))
                    }
                    Spacer().frame(height: 64)
                }
                .frame(width: geo.size.width)
                .opacity(shown ? 1 : 0)
                .offset(y: shown ? 0 : 18)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .onAppear {
            guard DjAnim.enabled else { shown = true; finished = true; return }
            start = Date()
            withAnimation(.easeOut(duration: 0.9 / Double(Self.speed)).delay(4.4 / Double(Self.speed))) { shown = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(vec?.dur ?? 8.5) / Double(Self.speed) + 0.2) { finished = true }
        }
    }
}

/** Vector data (splash_vec.json): outlines + pen path per piece, timings from the v4 preview. */
final class SplashVec {
    struct Comp: Decodable {
        let hanger: Bool
        let bbox: [Double]
        let win: [Double]
        let pw: Double
        let rings: [[Double]]
        let pen: [Double]
    }
    struct Doc: Decodable {
        let w: Double, h: Double, end: Double, gl0: Double, gl1: Double, dur: Double, logow: Double, cyf: Double
        let comps: [Comp]
    }
    static let shared: SplashVec? = {
        guard let u = Bundle.main.url(forResource: "splash_vec", withExtension: "json"),
              let d = try? Data(contentsOf: u), let doc = try? JSONDecoder().decode(Doc.self, from: d) else { return nil }
        return SplashVec(doc)
    }()

    let doc: Doc
    let dur: Float
    private let glyphs: [Path]
    init(_ d: Doc) {
        doc = d; dur = Float(d.dur)
        glyphs = d.comps.map { c in
            var p = Path()
            for a in c.rings where a.count >= 4 {
                p.move(to: CGPoint(x: a[0], y: a[1]))
                var q = 2
                while q + 1 < a.count { p.addLine(to: CGPoint(x: a[q], y: a[q + 1])); q += 2 }
                p.closeSubpath()
            }
            return p
        }
    }

    private func clamp(_ x: Double, _ a: Double = 0, _ b: Double = 1) -> Double { max(a, min(b, x)) }
    private func sstep(_ a: Double, _ b: Double, _ t: Double) -> Double {
        let x = clamp((t - a) / (b - a)); return x * x * x * (x * (6 * x - 15) + 10)
    }
    private func penEase(_ u0: Double, _ p: Double) -> Double {
        let u = clamp(u0)
        return (u > 0 && u < 1) ? pow(u, p) / (pow(u, p) + pow(1 - u, p)) : u
    }
    private func col(_ rgb: UInt32, _ a: Double) -> Color {
        Color(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255).opacity(a / 255)
    }

    func draw(_ ctx: inout GraphicsContext, _ size: CGSize, _ tf: Float) {
        let t = Double(tf)
        let W = Double(size.width), H = Double(size.height)
        let fk = W / 1290
        let s0 = doc.logow * W / doc.w
        let cx = W / 2, cy = doc.cyf * H
        let end = doc.end
        let breath = 0.5 + 0.5 * sin(t * 1.1)
        let push = 1 + 0.045 * sstep(0.2, end + 2, t) + 0.010 * sin(clamp((t - 3) / 4) * Double.pi) * (1 - sstep(6, 8.5, t))
        let gm = (doc.gl0 + doc.gl1) / 2, gwd = (doc.gl1 - doc.gl0) / 2.4
        let gb = exp(-pow((t - gm) / gwd, 2))
        let s = s0 * push
        for (i, comp) in doc.comps.enumerated() {
            if t < comp.win[0] { continue }
            var m = CGAffineTransform(translationX: cx, y: cy + (1 - sstep(0, end + 1, t)) * 22 * fk)
                .scaledBy(x: s, y: s).translatedBy(x: -doc.w / 2, y: -doc.h / 2)
            var sc = s
            if comp.hanger {
                let hp = CGPoint(x: (comp.bbox[0] + comp.bbox[2]) / 2, y: (comp.bbox[1] + comp.bbox[3]) / 2).applying(m)
                let k = 1 + 0.03 * sstep(0.2, end + 2, t)
                let extra = CGAffineTransform(translationX: hp.x, y: hp.y).scaledBy(x: k, y: k).translatedBy(x: -hp.x, y: -hp.y)
                    .concatenating(CGAffineTransform(translationX: 0, y: -8 * fk * sstep(0.2, end + 2, t)))
                m = m.concatenating(extra)
                sc = s * k
            }
            let u = penEase((t - comp.win[0]) / (comp.win[1] - comp.win[0]), comp.pw)
            let n = comp.pen.count / 3
            let kk = max(1, Int(u * Double(n)))
            let grow = sstep(comp.win[1], comp.win[1] + 0.45, t)
            var rv = Path()
            for j in 0..<min(kk, n) {
                let x = comp.pen[j * 3], y = comp.pen[j * 3 + 1], r = comp.pen[j * 3 + 2] * (1.22 + 3.0 * grow) + 0.9
                rv.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
            }
            let reveal = rv.applying(m)
            let dp = glyphs[i].applying(m)
            let bb = CGRect(x: comp.bbox[0], y: comp.bbox[1], width: comp.bbox[2] - comp.bbox[0], height: comp.bbox[3] - comp.bbox[1]).applying(m)
            let x0 = bb.minX, y0 = bb.minY, x1 = bb.maxX, y1 = bb.maxY
            ctx.drawLayer { l in
                l.clip(to: reveal)
                l.fill(dp, with: .linearGradient(Gradient(stops: [
                    .init(color: col(0xE6DAB6, 255), location: 0), .init(color: col(0xC8BB98, 255), location: 0.5),
                    .init(color: col(0x9F9170, 255), location: 1)]), startPoint: CGPoint(x: 0, y: y0), endPoint: CGPoint(x: 0, y: y1)),
                    style: FillStyle(eoFill: true))
                l.clip(to: dp, style: FillStyle(eoFill: true))
                let diag = (x1 - x0) + (y1 - y0)
                let pos = 0.5 + 0.5 * sin(t * 0.45 + Double(i) * 0.7)
                let bx = x0 - 0.3 * diag + pos * 1.6 * diag
                let box = CGRect(x: x0 - 5, y: y0 - 5, width: (x1 - x0) + 10, height: (y1 - y0) + 10)
                l.fill(Path(box), with: .linearGradient(Gradient(stops: [
                    .init(color: col(0xFFF3CF, 0), location: 0), .init(color: col(0xFFF3CF, 70 + 30 * breath), location: 0.5),
                    .init(color: col(0xFFF3CF, 0), location: 1)]), startPoint: CGPoint(x: bx, y: y1), endPoint: CGPoint(x: bx + 0.4 * diag, y: y0)))
                if gb > 0.002 {
                    let gp = sstep(doc.gl0, doc.gl1, t)
                    let gx0 = -0.2 * W + gp * 1.4 * W, gwid = 0.10 * W
                    let nx = cos(-0.35), ny = sin(-0.35)
                    l.blendMode = .plusLighter
                    l.fill(Path(box), with: .linearGradient(Gradient(stops: [
                        .init(color: col(0xFFF8E2, 0), location: 0), .init(color: col(0xFFF3CC, 200), location: 0.5),
                        .init(color: col(0xFFF8E2, 0), location: 1)]),
                        startPoint: CGPoint(x: gx0 - nx * gwid, y: cy - ny * gwid), endPoint: CGPoint(x: gx0 + nx * gwid, y: cy + ny * gwid)))
                    l.blendMode = .normal
                }
                let rw = max(fk, sc * 0.55)
                l.drawLayer { r in
                    r.translateBy(x: -rw * 0.7, y: -rw * 0.7)
                    r.stroke(dp, with: .color(col(0xFFF5D6, 150)), lineWidth: rw * 2)
                }
                l.drawLayer { r in
                    r.translateBy(x: rw * 0.7, y: rw * 0.8)
                    r.stroke(dp, with: .color(col(0x6A5E40, 110)), lineWidth: rw * 2)
                }
            }
        }
    }
}
