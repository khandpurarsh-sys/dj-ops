import XCTest
@testable import DressJetShop

/** Home feed plumbing (Android Feed.kt parity): collections parse, paging urls, merge/remaining. */
final class HomeFeedTests: XCTestCase {
    private func mk(_ id: Int64, _ created: String) -> DjProduct {
        DjProduct(id: id, handle: "h\(id)", title: "T\(id)", type: "", images: ["u"],
                  variants: [DjVariant(id: id * 10, title: "S", price: "100.00", available: true)],
                  createdAt: created, description: "")
    }

    func testParseCollections() {
        let json = #"{"collections":[{"handle":"polos","title":"Polos","image":{"src":"https://x/img.jpg"},"products_count":12},{"handle":"noimg","title":"No Image","products_count":3},{"handle":"","title":"Skip"}]}"#
        let cols = Feed.parseCollections(Data(json.utf8))
        XCTAssertEqual(2, cols.count)
        XCTAssertEqual(DjCollection(handle: "polos", title: "Polos", image: "https://x/img.jpg", productsCount: 12), cols[0])
        XCTAssertNil(cols[1].image)
        XCTAssertEqual("https://dressjet.com/products.json?limit=250", Feed.productsURL.absoluteString)
        XCTAssertEqual("https://dressjet.com/collections/polos/products.json?limit=250",
                       Feed.collectionProductsURL("polos").absoluteString)
        XCTAssertEqual("https://dressjet.com/products/handle-1.js", Feed.productJsURL("handle-1").absoluteString)
        XCTAssertEqual("https://dressjet.com/products.json?limit=30&page=3",
                       Feed.productsPageURL(3).absoluteString)
    }

    func testMergeDedupesById() {
        let a = [mk(1, "2026-01-01"), mk(2, "2026-01-02")]
        let b = [mk(2, "2026-01-02"), mk(3, "2026-01-03")]
        XCTAssertEqual([1, 2, 3], Feed.mergeProducts(a, b).map { $0.id })
        XCTAssertEqual([1, 2], Feed.mergeProducts(a, []).map { $0.id })
    }

    func testRemainingExcludesShown() {
        let all = [mk(1, "a"), mk(2, "b"), mk(3, "c")]
        XCTAssertEqual([3], Feed.remainingProducts(all, [all[0], all[1]]).map { $0.id })
    }

    func testHomeSectionHandlesOrder() {
        XCTAssertEqual(["all-new-jackets", "polos", "shoes", "trousers"], Feed.HOME_SECTION_HANDLES)
    }

    func testParseHeroMediaAlias() {
        XCTAssertNil(Feed.parseHeroMedia("<html><body>no video</body></html>"))
        let h = Feed.parseHeroMedia(#"<video data-src="//cdn/x.HD-1080p-7.2Mbps.mp4?v=0" poster="https://cdn/p.jpg"></video>"#)
        XCTAssertEqual("https://cdn/x.HD-1080p-7.2Mbps.mp4?v=0", h?.video)
        XCTAssertEqual("https://cdn/x.HD-720p-4.5Mbps.mp4?v=0", h?.video720)
    }
}

/** priceLabel: single selling price, "From" only on a real variant spread. */
final class PriceLabelTests: XCTestCase {
    private func mk(_ prices: [String]) -> DjProduct {
        DjProduct(id: 1, handle: "h", title: "T", type: "", images: ["u"],
                  variants: prices.enumerated().map { DjVariant(id: Int64($0.offset), title: "S\($0.offset)", price: $0.element, available: true) },
                  createdAt: "", description: "")
    }
    func testLabels() {
        XCTAssertEqual("₹3,990", Feed.priceLabel(mk(["3990.00"])))
        XCTAssertEqual("₹3,990", Feed.priceLabel(mk(["3990.00", "3990.00"])))
        XCTAssertEqual("From ₹2,990", Feed.priceLabel(mk(["3990.00", "2990.00"])))
        XCTAssertEqual("₹—", Feed.priceLabel(mk([])))
    }
}

/** Menu categories, store pages and the dock flip rule (Android parity pins). */
final class MenuAndDockTests: XCTestCase {
    func testMenuCategories() {
        XCTAssertEqual(["Jackets", "Polos", "Shoes", "Coming Soon"], Feed.MENU_CATEGORIES.map { $0.label })
        XCTAssertEqual(["all-new-jackets", "polos", "shoes", "shirt"], Feed.MENU_CATEGORIES.map { $0.handle })
    }

    func testStorePages() {
        XCTAssertEqual(["Exchange / Return", "Support", "Privacy Policy", "Return & Refund Policy",
                        "Shipping Policy", "Terms & Conditions"], Feed.STORE_PAGES.map { $0.title })
        XCTAssertEqual(5, Feed.STORE_PAGES.filter { PolicyContent.page(forURL: $0.url) != nil }.count,
                       "every dressjet.com page except the returns portal renders natively")
    }

    func testDockStaysGlass() {
        XCTAssertTrue(dockStaysGlass(heroBottom: 800, viewportEnd: 800, dockTouchPx: 40))
        XCTAssertTrue(dockStaysGlass(heroBottom: 761, viewportEnd: 800, dockTouchPx: 40))
        XCTAssertFalse(dockStaysGlass(heroBottom: 760, viewportEnd: 800, dockTouchPx: 40))
        XCTAssertFalse(dockStaysGlass(heroBottom: nil, viewportEnd: 800, dockTouchPx: 40))
    }
}
