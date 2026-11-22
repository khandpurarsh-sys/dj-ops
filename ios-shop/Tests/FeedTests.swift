import XCTest
@testable import DressJetShop

final class FeedTests: XCTestCase {
    private func snapshot() -> Data {
        let url = Bundle(for: FeedTests.self).url(forResource: "products-snapshot", withExtension: "json")!
        return try! Data(contentsOf: url)
    }

    func testParsesSnapshotKeepingVideoOnly() {
        // Parse keeps no-photo products (Android parseProducts parity): Repo.enrich owns
        // fetching their website poster and dropping only products with no visual at all.
        let products = Feed.parseProducts(snapshot())
        XCTAssertEqual(169, products.count)
        XCTAssertEqual(6, products.filter { $0.images.isEmpty }.count)
        XCTAssertTrue(products.allSatisfy { !$0.variants.isEmpty })
        XCTAssertTrue(products.allSatisfy { p in p.images.allSatisfy { $0.hasPrefix("http") } })
    }

    func testKeepsOnlyWebsiteFields() {
        let p = Feed.parseProducts(snapshot()).first!
        XCTAssertEqual("The hurlingham Chester tm", p.title)
        XCTAssertEqual(4, p.images.count)
        XCTAssertEqual(["S", "M", "L", "XL", "XXL"], p.sizes)
        XCTAssertEqual("5490.00", p.variants.first?.price)
        XCTAssertGreaterThan(p.variants.first?.id ?? 0, 0)
    }

    func testEmptyAndGarbageAreSafe() {
        XCTAssertEqual([], Feed.parseProducts(Data("{}".utf8)))
        XCTAssertEqual([], Feed.parseProducts(Data("{\"products\":[]}".utf8)))
        XCTAssertEqual([], Feed.parseProducts(Data("not json".utf8)))
        XCTAssertEqual([], Feed.parseProducts(Data("{\"products\":[{\"id\":1,\"title\":\"x\",\"images\":[]}]}".utf8)))
    }

    func testInrFormatsIndianGrouping() {
        XCTAssertEqual("₹5,490", Feed.inr("5490.00"))
        XCTAssertEqual("₹1,29,900", Feed.inr("129900.00"))
        XCTAssertEqual("₹1,299.50", Feed.inr("1299.50"))
        XCTAssertEqual("₹—", Feed.inr(""))
        XCTAssertEqual("₹—", Feed.inr("abc"))
    }

    func testPaiseConverts() {
        XCTAssertEqual(549000, Feed.paise("5490.00"))
        XCTAssertEqual(129950, Feed.paise("1299.50"))
        XCTAssertEqual(0, Feed.paise("abc"))
    }

    func testCartPermalinkUsesVariantQtyPairs() {
        let lines = [
            Feed.BagLine(variantId: 111, handle: "a", title: "A", size: "S", price: "100.00", image: "img", qty: 2),
            Feed.BagLine(variantId: 222, handle: "b", title: "B", size: "M", price: "200.00", image: "img", qty: 1),
        ]
        XCTAssertEqual("https://dressjet.com/cart/111:2,222:1", Feed.cartPermalink(lines))
    }

    func testDisplayTitleRendersTrademarkGlyph() {
        XCTAssertEqual("The hurlingham Chester™", Feed.displayTitle("The hurlingham Chester tm"))
        XCTAssertEqual("The hurlingham Chester™", Feed.displayTitle("The hurlingham Chester TM "))
        XCTAssertEqual("The Marlowe", Feed.displayTitle("The Marlowe"))
    }

    func testHtmlToTextDecodesTypographicEntities() {
        let out = Feed.htmlToText("<p>It&#8217;s &ldquo;here&rdquo; &hellip; now&mdash;today &amp; always</p>")
        XCTAssertEqual("It\u{2019}s \u{201C}here\u{201D} \u{2026} now\u{2014}today & always", out)
    }
}

final class BagStoreTests: XCTestCase {
    @MainActor
    func testAddRemoveCountTotalPersist() async {
        let defaults = UserDefaults(suiteName: "djshop.test.\(UUID().uuidString)")!
        let bag = Bag(defaults: defaults)
        let products = Feed.parseProducts({
            let url = Bundle(for: FeedTests.self).url(forResource: "products-snapshot", withExtension: "json")!
            return try! Data(contentsOf: url)
        }())
        let p = products.first!
        XCTAssertEqual(0, bag.count)
        bag.add(p, p.variants[0])
        bag.add(p, p.variants[0])
        bag.add(p, p.variants[1])
        XCTAssertEqual(3, bag.count)
        XCTAssertEqual(2, bag.lines.first { $0.variantId == p.variants[0].id }?.qty)
        let expectPaise = Feed.paise(p.variants[0].price) * 2 + Feed.paise(p.variants[1].price)
        XCTAssertEqual(expectPaise, bag.totalPaise)

        let bag2 = Bag(defaults: defaults) // persisted: a fresh Bag sees the same lines
        XCTAssertEqual(3, bag2.count)

        bag2.remove(p.variants[0].id)
        XCTAssertEqual(1, bag2.count)
        XCTAssertEqual(p.variants[1].id, bag2.lines.first?.variantId)
    }

    @MainActor
    func testCorruptStoredBagFallsBackToEmpty() async {
        let defaults = UserDefaults(suiteName: "djshop.test.\(UUID().uuidString)")!
        defaults.set(Data("{not json".utf8), forKey: "djshop.bag")
        XCTAssertEqual(0, Bag(defaults: defaults).count)
    }

    @MainActor
    func testTotalKeepsPaise() async {
        let defaults = UserDefaults(suiteName: "djshop.test.\(UUID().uuidString)")!
        let bag = Bag(defaults: defaults)
        let p = DjProduct(id: 1, handle: "h", title: "T", type: "", images: ["https://img/1.jpg"],
                          variants: [DjVariant(id: 9001, title: "M", price: "1299.99", available: true),
                                     DjVariant(id: 9002, title: "L", price: "129900.00", available: true)])
        bag.add(p, p.variants[0])
        XCTAssertEqual("₹1,299.99", bag.totalInr)
        bag.add(p, p.variants[1])
        XCTAssertEqual("₹1,31,199.99", bag.totalInr)
    }
}
