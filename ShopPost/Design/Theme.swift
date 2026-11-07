import SwiftUI
import UIKit

// Paleta cálida y neutra: fondo crema, tarjetas gris piedra, acento negro.
extension Color {
    static let spBackground = Color(light: 0xF7F6F2, dark: 0x111110)
    static let spCard = Color(light: 0xEFEEEA, dark: 0x1D1D1B)
    static let spCardStrong = Color(light: 0xE6E4DE, dark: 0x2A2A27)
    static let spChip = Color(light: 0xEDECE7, dark: 0x262624)
    static let spSurface = Color(light: 0xFFFFFF, dark: 0x2A2A27)
    static let spInk = Color(light: 0x111111, dark: 0xF5F4F0)
    static let spOnInk = Color(light: 0xFFFFFF, dark: 0x111111)
    static let spSecondary = Color(light: 0x7A7974, dark: 0x9C9B96)
    static let spTertiary = Color(light: 0xAAA9A3, dark: 0x6C6B67)
    static let spDivider = Color(light: 0xE3E1DB, dark: 0x2E2E2B)
    static let spGreen = Color(light: 0x2F7A4B, dark: 0x67C08B)
    static let spGreenSoft = Color(light: 0xE3EEE5, dark: 0x1E2E23)
    static let spRed = Color(light: 0xB8432F, dark: 0xE5786A)
    static let spRedSoft = Color(light: 0xF4E3DF, dark: 0x352220)
    static let spGold = Color(light: 0x9A6B3F, dark: 0xC99A6A)

    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }

    init(hexString: String) {
        let s = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        self.init(hex: UInt32(s, radix: 16) ?? 0x777777)
    }
}

/// Margen inferior de las pantallas (la barra de pestañas nativa ya reserva su sitio).
let tabBarClearance: CGFloat = 20

enum SPRadius {
    static let card: CGFloat = 20
    static let tile: CGFloat = 16
    static let small: CGFloat = 12
}

extension Font {
    // Estilos de texto del sistema: respetan el tamaño de letra elegido en Ajustes.
    static let spLargeTitle = Font.largeTitle.bold()
    static let spTitle = Font.title2.bold()
    static let spSection = Font.title3.weight(.semibold)
    static let spHeadline = Font.headline
    static let spBody = Font.body
    static let spSub = Font.subheadline
    static let spCaption = Font.caption
}

extension View {
    /// Tarjeta gris piedra muy redondeada (estilo principal de la app).
    func spCard(padding: CGFloat = 16, radius: CGFloat = SPRadius.card, color: Color = .spCard) -> some View {
        self.padding(padding)
            .background(color, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    func spScreen() -> some View {
        self.background(Color.spBackground.ignoresSafeArea())
    }

    func spSheet() -> some View {
        self.presentationBackground(Color.spBackground)
            .presentationCornerRadius(28)
    }
}

enum Money {
    static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "EUR"
        f.locale = Locale(identifier: "es_ES")
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        return f
    }()

    static func string(_ value: Double) -> String {
        formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f €", value)
    }

    static func unitString(_ value: Double?, unit: String?) -> String? {
        guard let value, value > 0, let unit, !unit.isEmpty else { return nil }
        return "\(string(value))/\(unit)"
    }

    static func percent(_ value: Double) -> String {
        let s = String(format: "%.0f", abs(value))
        return (value < 0 ? "−" : "+") + s + " %"
    }
}

enum Count {
    static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "es_ES")
        return f
    }()

    static func string(_ n: Int) -> String { formatter.string(from: NSNumber(value: n)) ?? "\(n)" }

    static func items(_ n: Int, _ one: String = "artículo", _ many: String = "artículos") -> String {
        "\(string(n)) \(n == 1 ? one : many)"
    }
}

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}
