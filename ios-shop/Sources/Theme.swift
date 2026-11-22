import SwiftUI

/** Approved tokens: navy #0E2C46 family, champagne #C0B090, cream #EFE6D2, pure white canvas. */
enum Dj {
    static let navy = Color(red: 0x0E/255, green: 0x2C/255, blue: 0x46/255)
    static let navyDeep = Color(red: 0x0A/255, green: 0x21/255, blue: 0x36/255)
    static let navyHi = Color(red: 0x16/255, green: 0x40/255, blue: 0x5F/255)
    static let gold = Color(red: 0xC0/255, green: 0xB0/255, blue: 0x90/255)
    static let gold2 = Color(red: 0xD8/255, green: 0xC9/255, blue: 0xA3/255)
    static let cream = Color(red: 0xEF/255, green: 0xE6/255, blue: 0xD2/255)
    static let ink2 = navy.opacity(0.60)
    static let ink3 = navy.opacity(0.45)
    static let line = navy.opacity(0.10)

    /// Product photo corner radius (grid tiles + rails). 236: 3 -> 12 (Arsh 3:19 PM:
    /// "rounded corners just a bit"), pending Arsh's preview OK before any build.
    static let tileRadius: CGFloat = 12

    static func cinzel(_ size: CGFloat) -> Font { .custom("Cinzel-Medium", size: size) }
    static func cormorant(_ size: CGFloat, italic: Bool = false) -> Font {
        .custom(italic ? "CormorantGaramond-MediumItalic" : "CormorantGaramond-Medium", size: size)
    }
    static func assistant(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch weight {
        case .semibold: return .custom("Assistant-SemiBold", size: size)
        case .medium: return .custom("Assistant-Medium", size: size)
        default: return .custom("Assistant-Regular", size: size)
        }
    }
}

/** Test switch: captures and reduced-motion render without motion. */
enum DjAnim { static var enabled = true }
