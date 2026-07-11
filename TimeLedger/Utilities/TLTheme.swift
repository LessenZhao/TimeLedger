import SwiftUI

enum TLTheme {
    static let cardRadius: CGFloat = 10
    static let listSpacing: CGFloat = 5
    static let rowVerticalPadding: CGFloat = 8
    static let swatchSize: CGFloat = 28
    static let actionButtonSize: CGFloat = 28
    static let segmentHeight: CGFloat = 30
    static let statusFont: Font = .system(size: 16, weight: .medium)
    static let projectNameFont: Font = .system(size: 15, weight: .semibold)
    static let metaFont: Font = .system(size: 13)
    static let segmentFont: Font = .system(size: 13, weight: .medium)
    static let statusIconSize: CGFloat = 20
    static let cardBackground = Color(.systemBackground)
    static let pageBackground = Color(.systemGroupedBackground)
}

extension Color {
    init(hex: String?) {
        guard let hex else {
            self = Color.accentColor.opacity(0.35)
            return
        }

        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard cleaned.count == 6 || cleaned.count == 8,
              let value = UInt64(cleaned, radix: 16) else {
            self = Color.accentColor.opacity(0.35)
            return
        }

        let hasAlpha = cleaned.count == 8
        let a = hasAlpha ? Double((value & 0xFF00_0000) >> 24) / 255 : 1
        let r = Double((value & 0x00FF_0000) >> 16) / 255
        let g = Double((value & 0x0000_FF00) >> 8) / 255
        let b = Double(value & 0x0000_00FF) / 255
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
