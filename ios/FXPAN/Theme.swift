import CoreText
import SwiftUI

enum Theme {
    static let bg = Color(hex: 0x0A0B0D)
    static let s1 = Color(hex: 0x121418)
    static let s2 = Color(hex: 0x191C21)
    static let s3 = Color(hex: 0x22262C)
    static let hair = Color(hex: 0x262A31)
    static let hair2 = Color(hex: 0x353A42)
    static let ink = Color(hex: 0xEEEBE3)
    static let ink2 = Color(hex: 0xCFCCC4)
    static let dim = Color(hex: 0x8C919A)
    static let faint = Color(hex: 0x5C616A)
    static let gold = Color(hex: 0xD8A735)
    static let goldDim = Color(hex: 0xD8A735, alpha: 0.16)
    static let goldInk = Color(hex: 0x1B1405)
    static let red = Color(hex: 0xE22B2B)
    static let transmit = Color(hex: 0x9A5CFF)
    static let reflect = Color(hex: 0xD8712F)
    static let ok = Color(hex: 0x5FCF80)
    static let warn = Color(hex: 0xF0A53A)
    static let err = Color(hex: 0xFF5B50)
    static let radius: CGFloat = 12
    static let radiusS: CGFloat = 8

    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Jost", size: size, relativeTo: .body).weight(weight)
    }
}

enum FontBook {
    static func register() {
        guard let url = Bundle.main.url(forResource: "Jost-VariableFont_wght", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
