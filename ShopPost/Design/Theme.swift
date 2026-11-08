import SwiftUI
import UIKit

// Paleta nativa de iOS: colores del sistema, con modo oscuro automático.
// Fondo blanco (negro en oscuro) y tarjetas en gris claro, como WhatsApp.
extension Color {
    static let spBackground = Color(uiColor: .systemBackground)
    static let spCard = Color(uiColor: .secondarySystemBackground)
    static let spCardStrong = Color(uiColor: .tertiarySystemFill)
    static let spChip = Color(uiColor: .tertiarySystemFill)
    static let spSurface = Color(uiColor: .secondarySystemBackground)
    static let spInk = Color(uiColor: .label)
    static let spOnInk = Color(uiColor: .systemBackground)
    static let spSecondary = Color(uiColor: .secondaryLabel)
    static let spTertiary = Color(uiColor: .tertiaryLabel)
    static let spDivider = Color(uiColor: .separator)
    static let spGreen = Color(uiColor: .systemGreen)
    static let spGreenSoft = Color(uiColor: .systemGreen).opacity(0.15)
    static let spRed = Color(uiColor: .systemRed)
    static let spRedSoft = Color(uiColor: .systemRed).opacity(0.12)
    static let spGold = Color(uiColor: .systemBrown)

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

/// Color de acento elegido por el usuario en Ajustes › Personalización (colores del sistema).
enum AccentChoice: String, CaseIterable, Codable, Identifiable {
    case blue, indigo, purple, pink, orange, yellow, teal, mint, brown, graphite
    var id: String { rawValue }

    var name: String {
        switch self {
        case .blue: "Azul"
        case .indigo: "Índigo"
        case .purple: "Morado"
        case .pink: "Rosa"
        case .orange: "Naranja"
        case .yellow: "Amarillo"
        case .teal: "Turquesa"
        case .mint: "Menta"
        case .brown: "Marrón"
        case .graphite: "Grafito"
        }
    }

    private var uiColor: UIColor {
        switch self {
        case .blue: .systemBlue
        case .indigo: .systemIndigo
        case .purple: .systemPurple
        case .pink: .systemPink
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .teal: .systemTeal
        case .mint: .systemMint
        case .brown: .systemBrown
        case .graphite: .label
        }
    }

    var color: Color { Color(uiColor: uiColor) }

    /// Texto e iconos sobre el acento: negro en los colores claros para que se lea bien.
    var onColor: Color {
        switch self {
        case .yellow, .mint: .black
        case .graphite: Color(uiColor: .systemBackground)
        default: .white
        }
    }
}

extension Color {
    /// Acento actual (botones principales, selección, pestaña activa).
    @MainActor static var spAccent: Color { Preferences.shared.accent.color }
    /// Texto e iconos sobre el acento.
    @MainActor static var spOnAccent: Color { Preferences.shared.accent.onColor }
}

/// Colores de marca de cada supermercado (fondo y letra), para etiquetas seleccionadas e insignias.
struct BrandStyle {
    let background: Color
    let foreground: Color

    @MainActor static func store(_ id: String?) -> BrandStyle? {
        guard let id else { return nil }
        switch id {
        case "mercadona": return BrandStyle(background: Color(hexString: "#00A650"), foreground: .white)
        case "consum": return BrandStyle(background: Color(hexString: "#FF6A13"), foreground: .white)
        case "eroski": return BrandStyle(background: Color(hexString: "#E30613"), foreground: .white)
        case "lidl": return BrandStyle(background: Color(hexString: "#0050AA"), foreground: Color(hexString: "#FFF000"))
        case "carrefour": return BrandStyle(background: Color(hexString: "#004E9F"), foreground: .white)
        case "dia": return BrandStyle(background: Color(hexString: "#E2001A"), foreground: .white)
        case "alcampo": return BrandStyle(background: Color(hexString: "#E2001A"), foreground: .white)
        default:
            guard let hex = CatalogService.shared.store(id)?.color else { return nil }
            return BrandStyle(background: Color(hexString: hex), foreground: .white)
        }
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
