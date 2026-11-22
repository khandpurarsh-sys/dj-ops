import XCTest
@testable import DressJetShop

final class FeedSearchTests: XCTestCase {
    private func product(_ id: Int64, _ title: String, _ type: String) -> DjProduct {
        DjProduct(id: id, handle: "h\(id)", title: title, type: type,
                  images: ["https://img/\(id).jpg"],
                  variants: [DjVariant(id: id * 10, title: "M", price: "100.00", available: true)])
    }

    func testSearchTokensTrimLowercaseSplit() {
        XCTAssertEqual(["long", "coat"], Feed.searchTokens("  Long \t COAT  "))
        XCTAssertEqual([], Feed.searchTokens("   "))
    }

    func testShoesFindsShoeViaHints() {
        // Title/type say neither "shoe" nor "shoes"; the hint "sneakers" hits via the group.
        let runner = product(1, "Street Runner", "")
        let belt = product(2, "Leather Belt", "")
        let pool = [runner, belt]
        XCTAssertEqual([runner], Feed.searchProducts(pool, hints: [1: "sneakers"], query: "shoes"))
        XCTAssertEqual([runner], Feed.searchProducts(pool, hints: [1: "sneakers"], query: "boots"))
    }

    func testLongCoatFallsBackToCategoryTokens() {
        // Nothing contains "long", so strict is empty; retry keeps only the category token.
        let overcoat = product(1, "Wool Overcoat", "Jackets")
        let chinos = product(2, "Slim Chinos", "Trousers")
        let pool = [overcoat, chinos]
        XCTAssertEqual([overcoat], Feed.searchProducts(pool, hints: [:], query: "long coat"))
    }

    func testStrictWinSkipsFallback() {
        let trench = product(1, "Long Trench Coat", "Jackets")
        let chinos = product(2, "Slim Chinos", "Trousers")
        XCTAssertEqual([trench], Feed.searchProducts([trench, chinos], hints: [:], query: "long coat"))
    }

    func testAllCategoryQueryKeepsEmptyStrict() {
        // Both tokens are category words; no fallback retry, empty strict result stands.
        let tee = product(1, "Plain Tee", "Shirts")
        XCTAssertEqual([], Feed.searchProducts([tee], hints: [:], query: "coat boots"))
    }

    func testUnmatchedQueryIsEmpty() {
        let tee = product(1, "Plain Tee", "Shirts")
        XCTAssertEqual([], Feed.searchProducts([tee], hints: [:], query: "zzz"))
        XCTAssertEqual([], Feed.searchProducts([], hints: [:], query: "shoes"))
    }

    func testTokenHitsSynonymMembersOnly() {
        XCTAssertTrue(Feed.tokenHits("slim denim jeans", "pants"))
        XCTAssertFalse(Feed.tokenHits("slim chinos", "hats"))
    }
}

final class FeedVideoTests: XCTestCase {
    private func js(_ media: String) -> Data { Data("{\"media\":[\(media)]}".utf8) }

    private func source(_ url: String, _ height: Int?) -> String {
        let h = height.map { ",\"height\":\($0)" } ?? ""
        return "{\"format\":\"mp4\",\"url\":\"\(url)\"\(h)}"
    }

    func testFirstMp4In481to900WinsImmediately() {
        // A taller 1080p source comes first; the in-range 720p still wins.
        let data = js("{\"media_type\":\"video\",\"sources\":[\(source("https://v/1080.mp4", 1080)),\(source("https://v/720.mp4", 720))],\"preview_image\":{\"src\":\"https://img/p.jpg\"}}")
        let v = Feed.parseProductVideo(data)
        XCTAssertEqual("https://v/720.mp4", v?.url)
        XCTAssertEqual("https://img/p.jpg", v?.poster)
    }

    func testFirstInRangeWinsOverEarlierSmallSource() {
        let data = js("{\"media_type\":\"video\",\"sources\":[\(source("https://v/200.mp4", 200)),\(source("https://v/600.mp4", 600))]}")
        XCTAssertEqual("https://v/600.mp4", Feed.parseProductVideo(data)?.url)
    }

    func testLargestHeightStrictGreaterFirstWinsTies() {
        // No source in 481...900: largest height wins; equal heights keep the first.
        let data = js("{\"media_type\":\"video\",\"sources\":[\(source("https://v/a.mp4", 1000)),\(source("https://v/b.mp4", 1000)),\(source("https://v/c.mp4", 300))]}")
        XCTAssertEqual("https://v/a.mp4", Feed.parseProductVideo(data)?.url)
    }

    func testSkipsNonMp4AndEmptyUrl() {
        let data = js("{\"media_type\":\"video\",\"sources\":[{\"format\":\"m3u8\",\"url\":\"https://v/x.m3u8\",\"height\":720},\(source("", 720)),\(source("https://v/ok.mp4", 480))]}")
        XCTAssertEqual("https://v/ok.mp4", Feed.parseProductVideo(data)?.url)
    }

    func testMissingHeightCountsAsZero() {
        let data = js("{\"media_type\":\"video\",\"sources\":[\(source("https://v/noh.mp4", nil)),\(source("https://v/h.mp4", 100))]}")
        XCTAssertEqual("https://v/h.mp4", Feed.parseProductVideo(data)?.url)
        let onlyNoH = js("{\"media_type\":\"video\",\"sources\":[\(source("https://v/noh.mp4", nil))]}")
        XCTAssertEqual("https://v/noh.mp4", Feed.parseProductVideo(onlyNoH)?.url)
    }

    func testNoVideoMediaIsNil() {
        XCTAssertNil(Feed.parseProductVideo(js("{\"media_type\":\"image\",\"src\":\"https://img/a.jpg\"}")))
        XCTAssertNil(Feed.parseProductVideo(Data("{}".utf8)))
        XCTAssertNil(Feed.parseProductVideo(Data("not json".utf8)))
    }

    func testEmptyPosterIsNil() {
        let data = js("{\"media_type\":\"video\",\"sources\":[\(source("https://v/720.mp4", 720))],\"preview_image\":{\"src\":\"\"}}")
        XCTAssertEqual("https://v/720.mp4", Feed.parseProductVideo(data)?.url)
        XCTAssertNil(Feed.parseProductVideo(data)?.poster)
    }

    func testPosterProtocolRelativePrefixedButVideoUrlVerbatim() {
        // Asymmetry per spec: poster "//" gets "https:", the video source URL stays as-is.
        let data = js("{\"media_type\":\"video\",\"sources\":[\(source("//v.cdn/x.mp4", 720))],\"preview_image\":{\"src\":\"//cdn.shop/p.jpg\"}}")
        let v = Feed.parseProductVideo(data)
        XCTAssertEqual("//v.cdn/x.mp4", v?.url)
        XCTAssertEqual("https://cdn.shop/p.jpg", v?.poster)
    }

    func testParseVideoPosterOnly() {
        let data = js("{\"media_type\":\"video\",\"sources\":[\(source("https://v/720.mp4", 720))],\"preview_image\":{\"src\":\"//cdn.shop/p.jpg\"}}")
        XCTAssertEqual("https://cdn.shop/p.jpg", Feed.parseMediaPoster(data))
        XCTAssertNil(Feed.parseMediaPoster(js("{\"media_type\":\"image\"}")))
    }
}

final class FeedHeroTests: XCTestCase {
    func testFirstVideoTagOnlyAndOpeningTagWins() {
        // Only the first <video> block is scanned; its opening-tag mp4 beats nested sources
        // and later tags do not count.
        let html = """
        <div><video poster="https://img/hero.jpg" data-src="https://vid/HD-1080p-7.2Mbps.mp4"><source src="https://vid/nested.mp4"></video></div>
        <video src="https://vid/second.mp4"></video>
        """
        let hero = Feed.extractHeroMedia(html)
        XCTAssertEqual("https://vid/HD-1080p-7.2Mbps.mp4", hero?.video)
        XCTAssertEqual("https://img/hero.jpg", hero?.poster)
    }

    func testNestedSourceMp4IsFound() {
        // The whole <video>...</video> block is scanned: a hero whose mp4 lives only in a
        // nested <source> (a common Shopify video-section shape) is discovered, not dropped.
        let html = #"<video poster="//cdn.shop/p.jpg"><source src="https://vid/nested.mp4"></video>"#
        let hero = Feed.extractHeroMedia(html)
        XCTAssertEqual("https://vid/nested.mp4", hero?.video)
        XCTAssertEqual("https://cdn.shop/p.jpg", hero?.poster)
    }

    func testAmpersandUnescapedAndProtocolRelativePrefixed() {
        let html = #"<video src="//vid.cdn/h.mp4?a=1&amp;b=2" poster="//cdn.shop/p.jpg?x=1&amp;y=2"></video>"#
        let hero = Feed.extractHeroMedia(html)
        XCTAssertEqual("https://vid.cdn/h.mp4?a=1&b=2", hero?.video)
        XCTAssertEqual("https://cdn.shop/p.jpg?x=1&y=2", hero?.poster)
    }

    func testFirstMp4AttrWins() {
        let html = #"<video data-src="https://vid/first.mp4" src="https://vid/second.mp4"></video>"#
        XCTAssertEqual("https://vid/first.mp4", Feed.extractHeroMedia(html)?.video)
    }

    func testNilWhenNeitherAttrPresent() {
        XCTAssertNil(Feed.extractHeroMedia("<video autoplay muted></video>"))
        XCTAssertNil(Feed.extractHeroMedia("<div>no video here</div>"))
        XCTAssertNil(Feed.extractHeroMedia(""))
    }

    func testVideo720SwapsOnlyThe1080pToken() {
        let withToken = Feed.extractHeroMedia(#"<video src="https://vid/HD-1080p-7.2Mbps.mp4"></video>"#)
        XCTAssertEqual("https://vid/HD-720p-4.5Mbps.mp4", withToken?.video720)
        let withoutToken = Feed.extractHeroMedia(#"<video src="https://vid/plain.mp4"></video>"#)
        XCTAssertNil(withoutToken?.video720) // Android takeIf: nil when the URL lacks the 1080p token
        XCTAssertNil(Feed.extractHeroMedia(#"<video poster="https://img/p.jpg"></video>"#)?.video720)
    }

    func testFallbackHeroPosterPorted() {
        XCTAssertEqual("https://dressjet.com/cdn/shop/files/preview_images/16d0f4acaad842c28c1e640319390006.thumbnail.0000000000.jpg?v=1735311853&width=1100", Feed.FALLBACK_HERO_POSTER)
    }
}
