import XCTest
@testable import DressJetShop

final class PolicyContentTests: XCTestCase {
    private let urls = [
        "https://dressjet.com/pages/shipping-policy",
        "https://dressjet.com/pages/return-and-refund-policy",
        "https://dressjet.com/pages/privacy-policy",
        "https://dressjet.com/pages/terms-and-conditions",
        "https://dressjet.com/pages/contact",
    ]

    func testEveryKnownURLResolvesWithItsTitle() {
        let titles = ["Shipping Policy", "Return & Refund Policy", "Privacy Policy", "Terms & Conditions", "Support"]
        for (url, title) in zip(urls, titles) {
            let page = PolicyContent.page(forURL: url)
            XCTAssertEqual(title, page?.title, url)
            XCTAssertFalse(page?.body.isEmpty ?? true, url)
        }
    }

    func testKeySentencesSurvive() {
        let shipping = PolicyContent.page(forURL: "https://dressjet.com/pages/shipping-policy")!.body
        XCTAssertTrue(shipping.contains("All orders are dispatched within 24 hours after payment confirmation."))
        XCTAssertTrue(shipping.contains("free shipping on all orders across India"))
        let returns = PolicyContent.page(forURL: "https://dressjet.com/pages/return-and-refund-policy")!.body
        XCTAssertTrue(returns.contains("Returns or exchanges are accepted within 7 days from the date of delivery."))
        XCTAssertTrue(returns.contains("up to ₹150 per item"))
        let privacy = PolicyContent.page(forURL: "https://dressjet.com/pages/privacy-policy")!.body
        XCTAssertTrue(privacy.contains("we value your privacy"))
        let terms = PolicyContent.page(forURL: "https://dressjet.com/pages/terms-and-conditions")!.body
        XCTAssertTrue(terms.contains("Prices listed are inclusive of applicable taxes unless stated otherwise."))
        let contact = PolicyContent.page(forURL: "https://dressjet.com/pages/contact")!.body
        XCTAssertTrue(contact.contains("support@dressjet.in"))
        XCTAssertTrue(contact.contains("+91 82880 72855"))
    }

    func testBodiesMatchKotlinRawStringsByteForByte() {
        // Anchors on the exact first and last bytes of each Kotlin raw string.
        let shipping = PolicyContent.page(forURL: "https://dressjet.com/pages/shipping-policy")!.body
        XCTAssertTrue(shipping.hasPrefix("# Shipping Policy\n\n- At Dressjet.in,"))
        XCTAssertTrue(shipping.hasSuffix("🕒 Support Hours: Monday – Saturday 10:00 AM – 5:00 PM"))
        XCTAssertFalse(shipping.hasSuffix("\n"))
        let contact = PolicyContent.page(forURL: "https://dressjet.com/pages/contact")!.body
        XCTAssertTrue(contact.hasPrefix("# Contact Us\n\nWe’d love to hear from you!"))
        XCTAssertTrue(contact.hasSuffix("🕒 Support Hours: Monday – Saturday 10:00 AM – 5:00 PM"))
    }

    func testSixNovEdits() {
        // Arsh 3:40 PM 6 Nov: 24-hour dispatch is true; drop the contact drafting artifact.
        let terms = PolicyContent.page(forURL: "https://dressjet.com/pages/terms-and-conditions")!.body
        XCTAssertTrue(terms.contains("- Orders are dispatched within 24 hours after payment confirmation."))
        XCTAssertFalse(terms.contains("2 - 3 days"))
        let contact = PolicyContent.page(forURL: "https://dressjet.com/pages/contact")!.body
        XCTAssertFalse(contact.contains("customize it further"))
        XCTAssertTrue(contact.contains("support@dressjet.in"))
    }

    func testExactCaseSensitiveLookupNoNormalization() {
        for url in urls {
            XCTAssertNil(PolicyContent.page(forURL: url + "/"), url)          // trailing slash misses
            XCTAssertNil(PolicyContent.page(forURL: url + "?utm=x"), url)     // query misses
            XCTAssertNil(PolicyContent.page(forURL: url.uppercased()), url)   // case change misses
        }
        XCTAssertNil(PolicyContent.page(forURL: "https://dressjet.com/pages/size-guide"))
        XCTAssertNil(PolicyContent.page(forURL: ""))
    }
}
