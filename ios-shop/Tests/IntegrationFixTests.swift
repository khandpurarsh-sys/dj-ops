import XCTest
@testable import DressJetShop

/** Integrator fixes over the peer slice (Android 214 parity), each pinned by a test. */
final class IntegrationFixTests: XCTestCase {
    private func js(_ media: String) -> Data { Data("{\"media\":[\(media)]}".utf8) }
    private func vid(_ sources: String, poster: String = "") -> String {
        "{\"media_type\":\"video\",\"sources\":[\(sources)],\"preview_image\":{\"src\":\"\(poster)\"}}"
    }
    private func src(_ h: Int?, _ u: String) -> String {
        h != nil ? "{\"format\":\"mp4\",\"height\":\(h!),\"url\":\"\(u)\"}" : "{\"format\":\"mp4\",\"url\":\"\(u)\"}"
    }

    func testFallsThroughToSecondVideoMedia() {
        // first video media has no usable source; Android continues to the next video media
        let data = js(vid("") + "," + vid(src(720, "https://v/second.mp4")))
        XCTAssertEqual("https://v/second.mp4", Feed.parseProductVideo(data)?.url)
    }

    func testMediaPosterReadsImageMediaToo() {
        // Android parseMediaPoster: first non-empty preview_image across ALL media types
        let data = js("{\"media_type\":\"image\",\"preview_image\":{\"src\":\"//cdn.shop/img.jpg\"}}")
        XCTAssertEqual("https://cdn.shop/img.jpg", Feed.parseMediaPoster(data))
    }

    func testHeroAttrsTolerateSpacesAndCase() {
        let hero = Feed.extractHeroMedia(#"<video SRC = "//cdn.shop/v.mp4" POSTER="//cdn.shop/p.jpg"></video>"#)
        XCTAssertEqual("https://cdn.shop/v.mp4", hero?.video)
        XCTAssertEqual("https://cdn.shop/p.jpg", hero?.poster)
    }

    func testHeroPosterAttrNeverBecomesVideo() {
        let hero = Feed.extractHeroMedia(#"<video poster="https://cdn.shop/weird.mp4.jpg" data-src="https://cdn.shop/v.mp4"></video>"#)
        XCTAssertEqual("https://cdn.shop/weird.mp4.jpg", hero?.poster)
        XCTAssertEqual("https://cdn.shop/v.mp4", hero?.video)
    }

    func testVideo720NilWhenUrlLacksTheToken() {
        XCTAssertNil(HeroMedia(video: "https://cdn.shop/plain.mp4", poster: nil).video720)
        XCTAssertEqual("https://cdn.shop/x.HD-720p-4.5Mbps-y.mp4",
                       HeroMedia(video: "https://cdn.shop/x.HD-1080p-7.2Mbps-y.mp4", poster: nil).video720)
    }
}
