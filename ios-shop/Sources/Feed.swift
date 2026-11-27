import Foundation

/** Live public product feed (dressjet.com/products.json) - models, parser, price and
 *  cart-permalink helpers. Website fields only: unknown means omit, never invent. */

struct DjVariant: Codable, Equatable {
    let id: Int64
    let title: String
    let price: String
    let available: Bool
}

struct DjProduct: Equatable, Identifiable {
    let id: Int64
    let handle: String
    let title: String
    let type: String
    let images: [String]
    let variants: [DjVariant]
    let createdAt: String
    let description: String
    var sizes: [String] { variants.map(\.title).uniqued() }

    init(id: Int64, handle: String, title: String, type: String, images: [String], variants: [DjVariant],
         createdAt: String = "", description: String = "") {
        self.id = id; self.handle = handle; self.title = title; self.type = type
        self.images = images; self.variants = variants
        self.createdAt = createdAt; self.description = description
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>(); return filter { seen.insert($0).inserted }
    }
}

enum Feed {
    static let productsURL = URL(string: "https://dressjet.com/products.json?limit=250")!
    static let collectionsURL = URL(string: "https://dressjet.com/collections.json?limit=50")!

    /** Parse the public products.json. Video-only products (no images) are KEPT - Repo
     *  enriches them with their real website poster via parseMediaPoster and drops only
     *  a product with no website visual at all (Android parseProducts parity). Products
     *  without variants are skipped. */
    static func parseProducts(_ data: Data) -> [DjProduct] {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = raw["products"] as? [[String: Any]] else { return [] }
        var out: [DjProduct] = []
        for p in arr {
            let imgs = ((p["images"] as? [[String: Any]]) ?? []).compactMap { $0["src"] as? String }.filter { !$0.isEmpty }
            let vars: [DjVariant] = ((p["variants"] as? [[String: Any]]) ?? []).compactMap { v in
                guard let id = (v["id"] as? NSNumber)?.int64Value,
                      let title = v["title"] as? String,
                      let price = v["price"] as? String else { return nil }
                return DjVariant(id: id, title: title, price: price, available: v["available"] as? Bool ?? true)
            }
            if vars.isEmpty { continue }
            out.append(DjProduct(
                id: (p["id"] as? NSNumber)?.int64Value ?? 0,
                handle: p["handle"] as? String ?? "",
                title: p["title"] as? String ?? "",
                type: p["product_type"] as? String ?? "",
                images: imgs,
                variants: vars,
                createdAt: p["created_at"] as? String ?? "",
                description: Feed.htmlToText(p["body_html"] as? String ?? "")))
        }
        return out
    }

    /** "5490.00" -> "₹5,490" (Indian grouping, no decimals when whole). Never shows compare-at. */
    static func inr(_ price: String) -> String {
        guard let v = Double(price) else { return "₹—" }
        let paiseTotal = paise(price)
        let whole = paiseTotal / 100
        let rem = Int(paiseTotal % 100)
        let grouped = indianGroup(whole)
        return rem == 0 ? "₹\(grouped)" : "₹\(grouped)." + String(format: "%02d", rem)
    }

    /** 129900 -> "1,29,900": last three digits, then groups of two. */
    static func indianGroup(_ whole: Int64) -> String {
        let s = String(whole)
        if s.count <= 3 { return s }
        var parts = [String(s.suffix(3))]
        var head = String(s.dropLast(3))
        while head.count > 2 { parts.insert(String(head.suffix(2)), at: 0); head = String(head.dropLast(2)) }
        if !head.isEmpty { parts.insert(head, at: 0) }
        return parts.joined(separator: ",")
    }

    static func paise(_ price: String) -> Int64 {
        Int64(((Double(price) ?? 0.0) * 100).rounded())
    }

    struct BagLine: Codable, Equatable {
        let variantId: Int64
        let handle: String
        let title: String
        let size: String
        let price: String
        let image: String
        var qty: Int
    }

    /** Shopify cart permalink: opens dressjet checkout prefilled with the bag. */
    static func cartPermalink(_ lines: [BagLine]) -> String {
        "https://dressjet.com/cart/" + lines.map { "\($0.variantId):\($0.qty)" }.joined(separator: ",")
    }

    /** Display form: a trailing "tm" becomes a proper trademark glyph. Website field unchanged. */
    static func displayTitle(_ title: String) -> String {
        title.replacingOccurrences(of: #"\s+[Tt][Mm]\s*$"#, with: "™", options: .regularExpression)
    }
}

// MARK: - Search, product video and hero media (ios-shop slice 1, peer-specified rules)

struct DjVideo: Equatable {
    let url: String   // source URL verbatim, never normalized
    let poster: String?
}

struct HeroMedia: Equatable {
    let video: String?
    let poster: String?

    /** 720p variant of the hero video URL: only the 1080p token is swapped. */
    var video720: String? {
        guard let video, video.contains("HD-1080p-7.2Mbps") else { return nil }
        return video.replacingOccurrences(of: "HD-1080p-7.2Mbps", with: "HD-720p-4.5Mbps")
    }
}

extension Feed {
    /** Exact synonym groups, per spec; category tokens are the tokens appearing in any group. */
    static let TYPE_SYNONYMS: [[String]] = [
        ["shoe", "shoes", "sneaker", "sneakers", "loafer", "loafers", "footwear", "boot", "boots"],
        ["jacket", "jackets", "coat", "coats", "blazer", "sherling", "shacket", "bomber"],
        ["polo", "polos", "tee", "tees", "tshirt", "t-shirt", "shirt", "shirts"],
        ["trouser", "trousers", "pants", "chinos", "jeans", "denim"],
    ]

    /** Ported from Android; callers substitute it when a hero video has no poster. */
    static let FALLBACK_HERO_POSTER = "https://dressjet.com/cdn/shop/files/preview_images/16d0f4acaad842c28c1e640319390006.thumbnail.0000000000.jpg?v=1735311853&width=1100"
    static let FALLBACK_HERO_VIDEO = "https://dressjet.com/cdn/shop/videos/c/vp/16d0f4acaad842c28c1e640319390006/16d0f4acaad842c28c1e640319390006.HD-1080p-7.2Mbps-40214913.mp4?v=0"

    /** Shopify body_html -> readable plain text for the native details sheet (paragraphs
     *  and bullets preserved) - Android htmlToText parity, same replacement order. */
    static func htmlToText(_ html: String) -> String {
        var t = html
        t = t.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        t = t.replacingOccurrences(of: "(?i)</p\\s*>", with: "\n\n", options: .regularExpression)
        t = t.replacingOccurrences(of: "(?i)<li[^>]*>", with: "\u{2022} ", options: .regularExpression)
        t = t.replacingOccurrences(of: "(?i)</li\\s*>", with: "\n", options: .regularExpression)
        t = t.replacingOccurrences(of: "(?s)<[^>]+>", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&nbsp;", with: " ")
        t = t.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
        t = t.replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'")
        t = t.replacingOccurrences(of: "&rsquo;", with: "\u{2019}").replacingOccurrences(of: "&#8217;", with: "\u{2019}")
        t = t.replacingOccurrences(of: "&lsquo;", with: "\u{2018}").replacingOccurrences(of: "&#8216;", with: "\u{2018}")
        t = t.replacingOccurrences(of: "&ldquo;", with: "\u{201C}").replacingOccurrences(of: "&#8220;", with: "\u{201C}")
        t = t.replacingOccurrences(of: "&rdquo;", with: "\u{201D}").replacingOccurrences(of: "&#8221;", with: "\u{201D}")
        t = t.replacingOccurrences(of: "&hellip;", with: "\u{2026}").replacingOccurrences(of: "&#8230;", with: "\u{2026}")
        t = t.replacingOccurrences(of: "&mdash;", with: "\u{2014}").replacingOccurrences(of: "&ndash;", with: "\u{2013}")
        t = t.replacingOccurrences(of: "&apos;", with: "'")
        t = t.replacingOccurrences(of: "[ \t]+", with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /** PDP details quoted verbatim from the site's own product page theme sections
     *  (dressjet.com product pages, fetched 5 Nov; match the website). */
    static let DISPATCH_LINE = "Dispatch within 24 hours - Sunday orders ship the next working day"
    static let SHIPPING_LINES = [
        "We offer fast and reliable shipping for all our clothing items. Orders are dispatched within 24 hours. If an order is placed on a non-working day (Sunday), it will be dispatched on the next working day.",
    ]
    static let REFUND_LINES = [
        "For eligible returns, refunds will be issued to the original payment method used for the purchase.",
        "Returns must be requested within 7 days of delivery.",
        "Products must be unused, in original condition, with all tags and packaging intact.",
        "\u{20B9}150 will be deducted per returned item as return shipping charges.",
        "Shoes and jackets are non-returnable and non-refundable - size exchange only.",
        "The first size exchange is free; any additional size exchange will require applicable shipping charges.",
        "Defective, damaged, or incorrect products may qualify for a replacement or appropriate resolution after verification.",
        "Approved refunds will generally be processed within 7\u{2013}10 business days after the returned product passes inspection and the return is approved.",
        "Refunds will normally be credited back through the same payment method used for the original purchase.",
    ]
    static let SUPPORT_LINES = [
        "Email: support@dressjet.in",
        "Phone: +91 82880 72855",
        "Support hours: Monday - Saturday, 10:00 AM - 5:00 PM",
    ]

    /** Tile price label: the selling price; a real spread across variants says "From". */
    static func priceLabel(_ p: DjProduct) -> String {
        let prices = p.variants.map { $0.price }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.uniqued()
        if prices.count <= 1 { return inr(prices.first ?? "") }
        let lo = prices.min { paise($0) < paise($1) } ?? prices[0]
        return "From " + inr(lo)
    }

    // MARK: home feed plumbing (Android Feed.kt parity)

    static let homeURL = URL(string: "https://dressjet.com/")!
    static let ALL_HANDLE = "__all__"
    /** Homepage curated rails, in order (Android Feed.HOME_SECTION_HANDLES). */
    static let HOME_SECTION_HANDLES = ["all-new-jackets", "polos", "shoes", "trousers"]

    /** Paged catalog for the endless home feed (Shopify pages start at 1). */
    static func productsPageURL(_ page: Int, _ limit: Int = 30) -> URL {
        URL(string: "https://dressjet.com/products.json?limit=\(limit)&page=\(page)")!
    }

    static func collectionProductsURL(_ handle: String) -> URL {
        URL(string: "https://dressjet.com/collections/\(handle)/products.json?limit=250")!
    }

    static func productJsURL(_ handle: String) -> URL {
        URL(string: "https://dressjet.com/products/\(handle).js")!
    }

    /** Append page results, dropping any id already present. */
    static func mergeProducts(_ existing: [DjProduct], _ next: [DjProduct]) -> [DjProduct] {
        if next.isEmpty { return existing }
        let seen = Set(existing.map { $0.id })
        return existing + next.filter { !seen.contains($0.id) }
    }

    /** Products not already shown in rails, for the endless All Products grid. */
    static func remainingProducts(_ all: [DjProduct], _ shown: [DjProduct]) -> [DjProduct] {
        let ids = Set(shown.map { $0.id })
        return all.filter { !ids.contains($0.id) }
    }

    // MARK: menu + store pages (Android Feed.kt parity)

    static let MENU_CATEGORIES: [MenuCategory] = [
        MenuCategory(label: "Jackets", handle: "all-new-jackets"),
        MenuCategory(label: "Polos", handle: "polos"),
        MenuCategory(label: "Shoes", handle: "shoes"),
        MenuCategory(label: "Coming Soon", handle: "shirt"),
    ]

    static let STORE_PAGES: [StorePage] = [
        StorePage(title: "Exchange / Return", url: "https://returns.logisy.tech/returns?encipherencode=gAAAAABp3ITnucZhUVL3mWQjNhGAzuIqqkwBaHXCINNtb4k7ZTGWNqZ1iU6b0yeEBqt-RxdGL49CclkXCt1AsUkM7YMdulgPfQ=="),
        StorePage(title: "Support", url: "https://dressjet.com/pages/contact"),
        StorePage(title: "Privacy Policy", url: "https://dressjet.com/pages/privacy-policy"),
        StorePage(title: "Return & Refund Policy", url: "https://dressjet.com/pages/return-and-refund-policy"),
        StorePage(title: "Shipping Policy", url: "https://dressjet.com/pages/shipping-policy"),
        StorePage(title: "Terms & Conditions", url: "https://dressjet.com/pages/terms-and-conditions"),
    ]

    /** Parse the public collections.json. Collections without an image are kept (the layout
     *  decides what to show); titles stay verbatim from the website. */
    static func parseCollections(_ data: Data) -> [DjCollection] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["collections"] as? [[String: Any]] else { return [] }
        var out: [DjCollection] = []
        for c in arr {
            guard let handle = c["handle"] as? String, !handle.isEmpty,
                  let title = c["title"] as? String, !title.isEmpty else { continue }
            let img = (c["image"] as? [String: Any])?["src"] as? String
            out.append(DjCollection(handle: handle, title: title,
                                    image: (img?.isEmpty == false) ? img : nil,
                                    productsCount: c["products_count"] as? Int ?? 0))
        }
        return out
    }

    /** Site hero from the homepage HTML (alias of extractHeroMedia, Android name parity). */
    static func parseHeroMedia(_ html: String) -> HeroMedia? { extractHeroMedia(html) }

    /** Newest first by the website's created_at (ISO-8601 sorts lexicographically). */
    static func newest(_ products: [DjProduct], _ n: Int) -> [DjProduct] {
        Array(products.sorted { $0.createdAt > $1.createdAt }.prefix(n))
    }

    // MARK: owner-controlled home order (Firestore config/homeOrder, edited on the order page)

    static let homeOrderURL = URL(string: "https://firestore.googleapis.com/v1/projects/dressjet-shop/databases/(default)/documents/config/homeOrder")!

    struct HomeOrder: Equatable {
        let order: [String]
        let hidden: Set<String>
    }

    /** Parse the Firestore REST document. nil when the body is not a homeOrder document. */
    static func parseHomeOrder(_ data: Data) -> HomeOrder? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fields = obj["fields"] as? [String: Any] else { return nil }
        func strings(_ key: String) -> [String] {
            let arr = ((fields[key] as? [String: Any])?["arrayValue"] as? [String: Any])?["values"] as? [[String: Any]] ?? []
            return arr.compactMap { $0["stringValue"] as? String }
        }
        return HomeOrder(order: strings("order"), hidden: Set(strings("hidden")))
    }

    /** Home grid order. Products the saved list does not know (new Shopify listings) stay on top,
     *  newest first; then the saved list in its order; hidden handles are dropped. With no saved
     *  order this is exactly newest-first, as before. */
    static func arranged(_ products: [DjProduct], _ o: HomeOrder?) -> [DjProduct] {
        let newestFirst = products.sorted { $0.createdAt > $1.createdAt }
        guard let o = o, !o.order.isEmpty else { return newestFirst }
        let rank = Dictionary(o.order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        let fresh = newestFirst.filter { rank[$0.handle] == nil }
        let listed = newestFirst.filter { rank[$0.handle] != nil }.sorted { rank[$0.handle]! < rank[$1.handle]! }
        return (fresh + listed).filter { !o.hidden.contains($0.handle) }
    }

    /** Trim, lowercase, split on whitespace. */
    static func searchTokens(_ query: String) -> [String] {
        query.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    private static func isCategoryToken(_ t: String) -> Bool {
        TYPE_SYNONYMS.contains { $0.contains(t) }
    }

    /** True when hay contains t, or - when t is in a synonym group - any member of that group. */
    static func tokenHits(_ hay: String, _ t: String) -> Bool {
        if hay.contains(t) { return true }
        for group in TYPE_SYNONYMS where group.contains(t) {
            return group.contains { hay.contains($0) }
        }
        return false
    }

    /** Strict: every token must hit. If nothing hits and the query mixes category words with
     *  descriptors ("long coat"), retry with only the category tokens. A query made of category
     *  words only keeps the empty strict result. Caller owns collection-title/handle hints. */
    static func searchProducts(_ pool: [DjProduct], hints: [Int64: String], query: String) -> [DjProduct] {
        let tokens = searchTokens(query)
        let catToks = tokens.filter { isCategoryToken($0) }
        func hay(_ p: DjProduct) -> String {
            (p.title + " " + p.type + " " + (hints[p.id] ?? "")).lowercased()
        }
        let strict = pool.filter { p in
            let h = hay(p)
            return tokens.allSatisfy { tokenHits(h, $0) }
        }
        if !strict.isEmpty { return strict }
        if catToks.isEmpty || catToks.count == tokens.count { return strict } // no descriptors to drop
        return pool.filter { p in
            let h = hay(p)
            return catToks.allSatisfy { tokenHits(h, $0) }
        }
    }

    /** Protocol-relative "//" gets "https:", anything else stays verbatim. */
    private static func posterURL(_ src: String) -> String {
        src.hasPrefix("//") ? "https:" + src : src
    }

    /** First video media in a Shopify product .js payload. Source order is iterated; non-mp4 and
     *  empty URLs are skipped. The FIRST mp4 with height 481...900 wins immediately; otherwise the
     *  largest height wins with strict greater-than (first wins ties); missing height counts as 0.
     *  The video source URL is returned as-is; only the poster is normalized. */
    static func parseProductVideo(_ jsJson: Data) -> DjVideo? {
        for media in videoMedia(jsJson) {
            let sources = (media["sources"] as? [[String: Any]]) ?? []
            var best: (url: String, height: Int)?
            for s in sources {
                guard (s["format"] as? String) == "mp4",
                      let url = s["url"] as? String, !url.isEmpty else { continue }
                let h = (s["height"] as? NSNumber)?.intValue ?? 0
                if (481...900).contains(h) { best = (url, h); break } // first in range wins immediately
                if best == nil || h > best!.height { best = (url, h) }
            }
            if let chosen = best {
                let posterSrc = ((media["preview_image"] as? [String: Any])?["src"] as? String) ?? ""
                return DjVideo(url: chosen.url, poster: posterSrc.isEmpty ? nil : posterURL(posterSrc))
            }
            // Android parity: a video media with no usable source falls through to the next one.
        }
        return nil
    }

    /** First non-empty preview_image src across ALL media entries (any type) - Android
     *  parseMediaPoster parity; Repo uses it to enrich video-only products. */
    static func parseMediaPoster(_ jsJson: Data) -> String? {
        guard let raw = try? JSONSerialization.jsonObject(with: jsJson) as? [String: Any],
              let media = raw["media"] as? [[String: Any]] else { return nil }
        for m in media {
            let src = ((m["preview_image"] as? [String: Any])?["src"] as? String) ?? ""
            if !src.isEmpty { return posterURL(src) }
        }
        return nil
    }

    private static func videoMedia(_ jsJson: Data) -> [[String: Any]] {
        guard let raw = try? JSONSerialization.jsonObject(with: jsJson) as? [String: Any],
              let media = raw["media"] as? [[String: Any]] else { return [] }
        return media.filter { ($0["media_type"] as? String) == "video" }
    }

    /** First <video...> block in homepage HTML. Attributes are read with the regex
     *  (data-src|src|poster)="..." across the whole <video>...</video> block - Shopify hero
     *  sections put the mp4 in nested <source> children, and tag-only scanning silently
     *  found no hero (always the hard-coded fallback). "&amp;" is unescaped to "&" and a
     *  leading "//" becomes "https:". Poster is the first poster attribute, video the
     *  first attribute URL containing ".mp4"; nil when both are absent. */
    static func extractHeroMedia(_ html: String) -> HeroMedia? {
        guard let openRange = html.range(of: #"<video\b[^>]*>"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        var end = openRange.upperBound
        if let closeRange = html.range(of: "</video>", options: [.caseInsensitive], range: openRange.upperBound..<html.endIndex) {
            end = closeRange.upperBound
        }
        let tag = String(html[openRange.lowerBound..<end])
        let attrRe = try! NSRegularExpression(pattern: #"(data-src|src|poster)\s*=\s*"([^"]+)""#, options: [.caseInsensitive])
        let nsRange = NSRange(tag.startIndex..., in: tag)
        var poster: String?
        var video: String?
        for m in attrRe.matches(in: tag, range: nsRange) {
            guard let nameRange = Range(m.range(at: 1), in: tag),
                  let valueRange = Range(m.range(at: 2), in: tag) else { continue }
            let name = String(tag[nameRange]).lowercased()
            var value = String(tag[valueRange])
            value = value.replacingOccurrences(of: "&amp;", with: "&")
            if value.hasPrefix("//") { value = "https:" + value }
            if name == "poster" { if poster == nil { poster = value } }
            else if video == nil, value.contains(".mp4") { video = value }
        }
        if video == nil && poster == nil { return nil }
        return HeroMedia(video: video, poster: poster)
    }
}

/** Menu category row: site nav label + collection handle. */
struct MenuCategory: Equatable { let label: String; let handle: String }

/** A page linked from the site's own footer/help menu. */
struct StorePage: Equatable { let title: String; let url: String }

/** Public collections.json entry; titles verbatim from the website. */
struct DjCollection: Equatable {
    let handle: String
    let title: String
    let image: String?
    let productsCount: Int
}
