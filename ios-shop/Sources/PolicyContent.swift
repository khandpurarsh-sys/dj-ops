import Foundation

/** Native policy page bodies, byte-identical to Android PolicyContent.kt
 *  (dressjet.com policy pages, fetched 5 Nov 2026; ported verbatim, no rewrites).
 *  Lookup is an exact case-sensitive URL match: trailing slash, query string or
 *  case differences are a miss, per peer spec.  Two deliberate 6 Nov edits per Arsh 3:40 PM ("just update the apps"): the terms
 *  shipping line now reads "dispatched within 24 hours after payment confirmation"
 *  (24-hour dispatch is true), and the contact page drops a leftover drafting artifact
 *  ("Let me know if you'd like to customize it further!"). */
enum PolicyContent {
    private static let pages: [String: (title: String, body: String)] = [
        "https://dressjet.com/pages/shipping-policy": (title: "Shipping Policy", body: shippingBody),
        "https://dressjet.com/pages/return-and-refund-policy": (title: "Return & Refund Policy", body: returnsBody),
        "https://dressjet.com/pages/privacy-policy": (title: "Privacy Policy", body: privacyBody),
        "https://dressjet.com/pages/terms-and-conditions": (title: "Terms & Conditions", body: termsBody),
        "https://dressjet.com/pages/contact": (title: "Support", body: contactBody),
    ]

    static func page(forURL url: String) -> (title: String, body: String)? {
        pages[url]
    }

    // https://dressjet.com/pages/shipping-policy
    private static let shippingBody: String =
        "# Shipping Policy\n" +
        "\n" +
        "- At Dressjet.in, we are committed to delivering your orders quickly and securely. Our goal is to ensure a smooth and reliable shopping experience for every customer.\n" +
        "\n" +
        "### 1. Fast Dispatch\n" +
        "\n" +
        "⚡ Fast Dispatch Guarantee\n" +
        "\n" +
        "- All orders are dispatched within 24 hours after payment confirmation.\n" +
        "- Orders placed on Sunday or public holidays will be dispatched on the next working day.\n" +
        "\n" +
        "### 2. Delivery Time\n" +
        "\n" +
        "Estimated delivery timelines across India:\n" +
        "\n" +
        "- Standard Delivery: 5–7 business days for most locations.\n" +
        "- Remote Areas: Delivery may take 7–10 business days depending on courier availability.\n" +
        "\n" +
        "### 3. Shipping Charges\n" +
        "\n" +
        "- Free Shipping: We offer free shipping on all orders across India.\n" +
        "- No Hidden Fees: The price shown at checkout is the final amount you pay.\n" +
        "\n" +
        "### 4. Delivery Partners\n" +
        "\n" +
        "We partner with reliable courier services to ensure safe and timely delivery:\n" +
        "\n" +
        "- Delhivery\n" +
        "- Blue Dart\n" +
        "- Ecom Express\n" +
        "\n" +
        "### 5. Order Tracking\n" +
        "\n" +
        "Once your order is shipped, you will receive a tracking number via email or SMS.\n" +
        "\n" +
        "You can track your order using the link provided in the notification or through our Order Tracking page.\n" +
        "\n" +
        "### 6. Delivery Locations\n" +
        "\n" +
        "We currently ship to all serviceable pin codes across India.\n" +
        "\n" +
        "At this time, international shipping is not available.\n" +
        "\n" +
        "### 7. Failed Delivery Attempts\n" +
        "\n" +
        "If delivery fails due to incorrect address details or recipient unavailability:\n" +
        "\n" +
        "- Our courier partner may attempt re-delivery.\n" +
        "- If the package is returned to us, additional shipping charges may apply for re-shipment.\n" +
        "\n" +
        "### 8. Damaged or Missing Items\n" +
        "\n" +
        "If your order arrives damaged or with missing items, please notify us within 48 hours of delivery.\n" +
        "\n" +
        "Kindly email us with your order details and photos of the package.\n" +
        "\n" +
        "📧 support@dressjet.in\n" +
        "\n" +
        "### 9. Contact Us\n" +
        "\n" +
        "For any shipping-related queries, please contact us:\n" +
        "\n" +
        "📧 Email: support@dressjet.in\n" +
        "\n" +
        "##### Need Help? We're Here for You! \n" +
        "\n" +
        "Have questions or need assistance? Feel free to contact our support team anytime during working hours.\n" +
        "\n" +
        "📧 Email: support@dressjet.in \n" +
        "\n" +
        "📞 Phone: +91 82880 72855 (+918288072855)\n" +
        "\n" +
        "🕒 Support Hours: Monday – Saturday 10:00 AM – 5:00 PM"

    // https://dressjet.com/pages/return-and-refund-policy
    private static let returnsBody: String =
        "# Return and Refund Policy\n" +
        "\n" +
        "At DressJet.in, customer satisfaction is our top priority. If you’re not fully satisfied with your purchase, we’re here to help with a straightforward return and refund process.\n" +
        "\n" +
        "#### 1.1 Timeframe\n" +
        "\n" +
        "- Returns or exchanges are accepted within 7 days from the date of delivery.\n" +
        "\n" +
        "#### 1.2 Reverse Shipment Fee\n" +
        "\n" +
        "- A fee of up to ₹150 per item may be deducted as per our Fair Usage Policy.\n" +
        "\n" +
        "#### 1.3 Return Pickup Attempts\n" +
        "\n" +
        "- Return pickups will be scheduled within 24–48 hours from the date of your request.\n" +
        "- A maximum of three pickup attempts will be made.\n" +
        "\n" +
        "#### 1.4 Service Availability\n" +
        "\n" +
        "- Reverse pickup services are subject to availability in your area.\n" +
        "\n" +
        "#### 1.5 Eligibility for Returns\n" +
        "\n" +
        "- Items must meet the following conditions: \n" +
        "\n" +
        "- Unused and in their original condition.\n" +
        "- Returned with the original packaging, tags, and invoice.\n" +
        "- - Leather Jackets - Store Credit Only Policy\n" +
        "\n" +
        "Please note that leather jacket purchases are eligible for store credit refunds only. Due to the premium nature and specialized care requirements of leather products, we do not offer cash refunds on leather jackets. Returns of leather jackets in original, unworn condition may be exchanged for store credit that can be used toward future purchases.\n" +
        "\n" +
        "#### 1.6 Non-Returnable Items\n" +
        "\n" +
        "The following items are not eligible for return:\n" +
        "\n" +
        "- Intimate apparel, personal care items, and hygiene-related products.\n" +
        "- Customized or personalized products.\n" +
        "- Clearance or “final sale” items.\n" +
        "\n" +
        "#### 1.7 Return Process\n" +
        "\n" +
        "1. Initiate Return:\n" +
        "\n" +
        "- Email us at 📧 support@dressjet.in with your order number and reason for return.\n" +
        "2. Return Confirmation:\n" +
        "\n" +
        "- Once your request is approved, we’ll arrange a return pickup or provide instructions for self-shipping.\n" +
        "3. Inspection and Approval:\n" +
        "\n" +
        "- After receiving the returned item, our team will inspect it to ensure it meets the return eligibility criteria.\n" +
        "\n" +
        "#### 2.1 Refund Eligibility\n" +
        "\n" +
        "Leather Jackets - Store Credit Only Policy\n" +
        "\n" +
        "Please note that leather jacket purchases are eligible for store credit refunds only. Due to the premium nature and specialized care requirements of leather products, we do not offer cash refunds on leather jackets. Returns of leather jackets in original, unworn condition may be exchanged for store credit that can be used toward future purchases.\n" +
        "\n" +
        "- Refunds are processed only for items that pass the inspection process.\n" +
        "- If an item is deemed ineligible for return, it will be sent back to you.\n" +
        "\n" +
        "For COD Orders:\n" +
        "\n" +
        "- Refunds will be transferred to your bank account or issued as store credit.\n" +
        "- You will need to provide your bank details during the return initiation process.\n" +
        "\n" +
        "For Prepaid Orders:\n" +
        "\n" +
        "- Refunds will be credited to your original payment method.\n" +
        "\n" +
        "#### 2.3 Refund Timeline\n" +
        "\n" +
        "- Refunds are processed within 7–10 business days after the returned item is approved.\n" +
        "\n" +
        "### 3. RETURN SHIPPING CHARGES\n" +
        "\n" +
        "- Defective/Damaged Items:\n" +
        "\n" +
        "- Return shipping charges will be covered by DressJet.in.\n" +
        "- Other Returns:\n" +
        "\n" +
        "- Customers are responsible for the return shipping charges, unless otherwise specified.\n" +
        "\n" +
        "### 4. EXCHANGE POLICY\n" +
        "\n" +
        "- Exchanges are accepted for size or color changes, subject to product availability.\n" +
        "- The process for exchanges is the same as the return process.\n" +
        "\n" +
        "### 5. CONTACT US\n" +
        "\n" +
        "For any questions or assistance, feel free to reach out to us: 📧 Email: support@dressjet.in \n" +
        "\n" +
        "##### Need Help? We're Here for You! \n" +
        "\n" +
        "Have questions or need assistance? Feel free to contact our support team anytime during working hours.\n" +
        "\n" +
        "📧 Email: support@dressjet.in \n" +
        "\n" +
        "📞 Phone: +91 82880 72855 (+918288072855)\n" +
        "\n" +
        "🕒 Support Hours: Monday – Saturday 10:00 AM – 5:00 PM"

    // https://dressjet.com/pages/privacy-policy
    private static let privacyBody: String =
        "# Privacy Policy\n" +
        "\n" +
        "At Dressjet.in, we value your privacy and are committed to protecting your personal information. This policy outlines how we collect, use, and safeguard your data.\n" +
        "\n" +
        "#### 1.1 Information We Collect\n" +
        "\n" +
        "- Personal details like name, address, phone number, and email.\n" +
        "- Payment details during transactions.\n" +
        "- Browsing behavior through cookies and analytics.\n" +
        "\n" +
        "#### 1.2 How We Use Your Information\n" +
        "\n" +
        "- To process orders and deliver products.\n" +
        "- To improve your shopping experience.\n" +
        "- For marketing and promotional activities (with your consent).\n" +
        "\n" +
        "#### 1.3 Data Security\n" +
        "\n" +
        "We implement strict measures to protect your data from unauthorized access or misuse.\n" +
        "\n" +
        "#### 1.4 Contact Us\n" +
        "\n" +
        "For privacy-related concerns: 📧 Email: support@dressjet.in \n" +
        "\n" +
        "##### Need Help? We're Here for You! \n" +
        "\n" +
        "Have questions or need assistance? Feel free to contact our support team anytime during working hours.\n" +
        "\n" +
        "📧 Email: support@dressjet.in \n" +
        "\n" +
        "📞 Phone: +91 82880 72855 (+918288072855)\n" +
        "\n" +
        "🕒 Support Hours: Monday – Saturday 10:00 AM – 5:00 PM"

    // https://dressjet.com/pages/terms-and-conditions
    private static let termsBody: String =
        "#### 1. Use of the Website\n" +
        "\n" +
        "#### 2. Orders and Payments\n" +
        "\n" +
        "- All orders are subject to acceptance and availability.\n" +
        "- Prices listed are inclusive of applicable taxes unless stated otherwise.\n" +
        "- Payments are processed securely through third-party gateways.\n" +
        "\n" +
        "#### 3. Shipping and Delivery\n" +
        "\n" +
        "- Orders are dispatched within 24 hours after payment confirmation.\n" +
        "- Delivery timelines may vary based on location and courier partners.\n" +
        "\n" +
        "#### 4. Returns and Refunds\n" +
        "\n" +
        "Refer to our Return and Refund Policy for detailed information.\n" +
        "\n" +
        "#### 5. Intellectual Property\n" +
        "\n" +
        "All content on Dressjet.in, including text, images, and logos, is the property of Dressjet.in and protected under applicable copyright laws.\n" +
        "\n" +
        "#### 6. Limitation of Liability\n" +
        "\n" +
        "Dressjet.in is not liable for indirect, incidental, or consequential damages arising from the use of our website or services.\n" +
        "\n" +
        "#### 7. Changes to Terms\n" +
        "\n" +
        "We reserve the right to update these terms without prior notice.\n" +
        "\n" +
        "##### Need Help? We're Here for You! \n" +
        "\n" +
        "Have questions or need assistance? Feel free to contact our support team anytime during working hours.\n" +
        "\n" +
        "📧 Email: support@dressjet.in \n" +
        "\n" +
        "📞 Phone: +91 82880 72855 (+918288072855)\n" +
        "\n" +
        "🕒 Support Hours: Monday – Saturday 10:00 AM – 5:00 PM"

    // https://dressjet.com/pages/contact
    private static let contactBody: String =
        "# Contact Us\n" +
        "\n" +
        "We’d love to hear from you! Whether you have questions about our products, need assistance with an order, or want to share feedback, our team is here to help. 📧 Email: support@dressjet.in 📞 Call us: +91 82880 72855 \n" +
        "\n" +
        "Feel free to reach out anytime, and we’ll get back to you as soon as possible. Thank you for choosing DressJet!\n" +
        "\n" +
                "\n" +
        "##### Need Help? We're Here for You! \n" +
        "\n" +
        "Have questions or need assistance? Feel free to contact our support team anytime during working hours.\n" +
        "\n" +
        "📧 Email: support@dressjet.in \n" +
        "\n" +
        "📞 Phone: +91 82880 72855 (+918288072855)\n" +
        "\n" +
        "🕒 Support Hours: Monday – Saturday 10:00 AM – 5:00 PM"

}
