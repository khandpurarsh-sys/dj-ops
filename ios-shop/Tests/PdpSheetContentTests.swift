import XCTest
@testable import DressJetShop

/** PDP sheet content (Android 214 parity): htmlToText, verbatim lines, createdAt. */
final class PdpSheetContentTests: XCTestCase {
    func testHtmlToTextParagraphsAndBullets() {
        XCTAssertEqual("Hello\n\nWorld", Feed.htmlToText("<p>Hello</p><p>World</p>"))
        XCTAssertEqual("\u{2022} one\n\u{2022} two", Feed.htmlToText("<ul><li>one</li><li>two</li></ul>"))
        XCTAssertEqual("a & b < c", Feed.htmlToText("a &amp; b &lt; c"))
        XCTAssertEqual("", Feed.htmlToText(""))
        XCTAssertEqual("line one\nline two", Feed.htmlToText("line one<br>line two<br/>"))
    }

    func testSnapshotParsesCreatedAtAndDescription() {
        let url = Bundle(for: PdpSheetContentTests.self).url(forResource: "products-snapshot", withExtension: "json")!
        let products = Feed.parseProducts(try! Data(contentsOf: url))
        XCTAssertTrue(products.allSatisfy { !$0.createdAt.isEmpty })
        // newest sorts by created_at descending, ISO lexicographic
        let top = Feed.newest(products, 5)
        XCTAssertEqual(5, top.count)
        XCTAssertTrue(zip(top, top.dropFirst()).allSatisfy { $0.createdAt >= $1.createdAt })
    }

    func testDispatchLineVerbatim() {
        XCTAssertEqual("Dispatch within 24 hours - Sunday orders ship the next working day", Feed.DISPATCH_LINE)
        XCTAssertEqual(9, Feed.REFUND_LINES.count)
        XCTAssertEqual(3, Feed.SUPPORT_LINES.count)
        XCTAssertEqual(1, Feed.SHIPPING_LINES.count)
    }
}
