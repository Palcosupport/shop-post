import SwiftUI

// MARK: - Cabeceras

struct BrandHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Shop Post")
                .font(.headline)
                .tracking(1.6)
            Text("TU LISTA DE LA COMPRA")
                .font(.caption2)
                .tracking(1.6)
                .foregroundStyle(Color.spSecondary)
        }
    }
}

struct ScreenTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.spLargeTitle).foregroundStyle(Color.spInk)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle).font(.spSub).foregroundStyle(Color.spSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.spSection).foregroundStyle(Color.spInk)
                if let subtitle { Text(subtitle).font(.spCaption).foregroundStyle(Color.spSecondary) }
            }
            Spacer()
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.spSub)
                        .foregroundStyle(Color.spAccent)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct SectionLinkHeader<V: Hashable>: View {
    let title: String
    var subtitle: String?
    let value: V

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.spSection).foregroundStyle(Color.spInk)
                if let subtitle { Text(subtitle).font(.spCaption).foregroundStyle(Color.spSecondary) }
            }
            Spacer()
            NavigationLink(value: value) {
                Text("Ver todo")
                    .font(.spSub)
                    .foregroundStyle(Color.spAccent)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Botones

struct CircleButton: View {
    let systemName: String
    var filled = false
    var size: CGFloat = 36
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(filled ? Color.spOnAccent : Color.spInk)
                .frame(width: size, height: size)
                .background(filled ? Color.spAccent : Color.spChip, in: Circle())
        }
        .buttonStyle(PressableStyle())
    }
}

struct PrimaryButton: View {
    let title: String
    var systemName: String?
    var style: Style = .dark
    let action: () -> Void

    enum Style { case dark, soft }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemName { Image(systemName: systemName) }
                Text(title)
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(style == .dark ? Color.spOnAccent : Color.spInk)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .background(style == .dark ? Color.spAccent : Color.spCardStrong,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Chips

struct Chip: View {
    let title: String
    var selected = false
    var icon: String? = nil
    /// Colores propios al seleccionarla (p. ej. la marca del supermercado); si no, el acento.
    var brand: BrandStyle? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Text(icon) }
                Text(title).lineLimit(1)
            }
            .font(.subheadline.weight(selected ? .semibold : .regular))
            .foregroundStyle(selected ? (brand?.foreground ?? Color.spOnAccent) : Color.spInk)
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .background(selected ? (brand?.background ?? Color.spAccent) : Color.spChip, in: Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

struct ChipBar<ID: Hashable>: View {
    let items: [(id: ID, title: String, icon: String?)]
    @Binding var selection: ID
    var brand: (ID) -> BrandStyle? = { _ in nil }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.id) { item in
                    Chip(title: item.title, selected: selection == item.id, icon: item.icon, brand: brand(item.id)) {
                        withAnimation(.snappy) { selection = item.id }
                        Haptics.tap()
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollClipDisabled()
        .padding(.horizontal, -16)
    }
}

// MARK: - Filas de opciones (hojas y perfil)

struct OptionRow: View {
    let icon: String
    let title: String
    var subtitle: String?
    var tint: Color = .spInk
    var circled = false
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(tint)
                .frame(width: circled ? 36 : 24, height: circled ? 36 : 24)
                .background { if circled { Circle().fill(Color.spSurface) } }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body).foregroundStyle(Color.spInk)
                if let subtitle {
                    Text(subtitle).font(.footnote).foregroundStyle(Color.spSecondary).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing).font(.spSub.weight(.medium)).foregroundStyle(Color.spSecondary)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.spTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, circled ? 10 : 13)
        .background(Color.spCard, in: RoundedRectangle(cornerRadius: SPRadius.card, style: .continuous))
        .contentShape(Rectangle())
    }
}

// MARK: - Indicadores

struct StatTile: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).font(.body).foregroundStyle(Color.spInk)
            Text(value).font(.title3.weight(.semibold)).foregroundStyle(Color.spInk)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.spCaption).foregroundStyle(Color.spSecondary).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
        .padding(12)
        .background(Color.spCard, in: RoundedRectangle(cornerRadius: SPRadius.tile, style: .continuous))
    }
}

struct ProgressLine: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.spCardStrong)
                Capsule().fill(Color.spAccent).frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: 4)
        .animation(.snappy, value: value)
    }
}

struct Badge: View {
    let text: String
    var color: Color = .spRed
    var soft: Color = .spRedSoft
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.caption2.weight(.bold)) }
            Text(text).lineLimit(1)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .frame(minHeight: 20)
        .background(soft, in: Capsule())
    }
}

// MARK: - Supermercados

struct StoreBadge: View {
    let storeId: String?
    var size: CGFloat = 28

    var body: some View {
        let info = storeId.flatMap { CatalogService.shared.store($0) }
        let name = info?.name ?? storeId?.capitalized ?? "?"
        let brand = BrandStyle.store(storeId)
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: size * 0.48, weight: .bold, design: .rounded))
            .foregroundStyle(brand?.foreground ?? .white)
            .frame(width: size, height: size)
            .background(Circle().fill(brand?.background ?? Color.spSecondary))
            .accessibilityLabel(name)
    }
}

struct StoreName: View {
    let storeId: String?
    var body: some View {
        HStack(spacing: 6) {
            StoreBadge(storeId: storeId, size: 18)
            Text(storeId.flatMap { CatalogService.shared.store($0)?.name } ?? storeId?.capitalized ?? "Sin supermercado")
                .font(.spCaption)
                .foregroundStyle(Color.spSecondary)
        }
    }
}

// MARK: - Imágenes

struct ProductImage: View {
    @Environment(\.colorScheme) private var scheme
    let url: URL?
    var padding: CGFloat = 10
    var placeholderEmoji: String = "🛒"

    var body: some View {
        // Ocupa siempre todo el hueco (también mientras carga o si falla) para no descuadrar las tarjetas.
        ZStack {
            Color.clear
            // Sin URL, AsyncImage se quedaría en blanco: se muestra el emoji de la categoría.
            if url == nil { placeholder } else { image }
        }
    }

    private var placeholder: some View {
        Text(placeholderEmoji).font(.system(size: 30)).opacity(0.6)
    }

    private var image: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
            switch phase {
            case .success(let image):
                // "multiply" elimina el fondo blanco de las fotos de producto: parecen recortadas sobre la tarjeta.
                // En modo oscuro se apoya en una placa clara para que el fondo blanco no destaque.
                let img = image.resizable().scaledToFit().blendMode(.multiply)
                if scheme == .light {
                    img.padding(padding)
                } else {
                    ZStack { Color.white; img.padding(6) }
                        .compositingGroup()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(padding)
                }
            case .failure:
                placeholder
            default:
                Color.clear
            }
        }
    }
}

/// Fondo blanco redondeado para la imagen pequeña de un producto.
struct Thumb: View {
    let url: URL?
    var size: CGFloat = 56
    var emoji = "🛒"

    var body: some View {
        ProductImage(url: url, padding: 6, placeholderEmoji: emoji)
            .frame(width: size, height: size)
            .background(Color.spSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Precio

struct PriceLabel: View {
    let price: Double
    var strike: Double?
    var size: CGFloat = 17

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(Money.string(price))
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(strike != nil ? Color.spGreen : Color.spInk)
            if let strike {
                Text(Money.string(strike))
                    .font(.system(size: size * 0.75))
                    .strikethrough()
                    .foregroundStyle(Color.spTertiary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

// MARK: - Cantidad

struct QuantityControl: View {
    let quantity: Int
    var compact = false
    let onChange: (Int) -> Void

    var body: some View {
        let h: CGFloat = compact ? 28 : 32
        if quantity == 0 {
            Button { onChange(1) } label: {
                Image(systemName: "plus")
                    .font(.system(size: compact ? 13 : 15, weight: .semibold))
                    .foregroundStyle(Color.spOnAccent)
                    .frame(width: h, height: h)
                    .background(Color.spAccent, in: Circle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Añadir a la cesta")
        } else {
            HStack(spacing: 0) {
                Button { onChange(quantity - 1) } label: {
                    Image(systemName: quantity == 1 ? "trash" : "minus")
                        .font(.system(size: compact ? 11 : 13, weight: .semibold))
                        .frame(width: h, height: h)
                }
                Text("\(quantity)")
                    .font(.system(size: compact ? 13 : 15, weight: .semibold))
                    .monospacedDigit()
                    .frame(minWidth: 18)
                Button { onChange(quantity + 1) } label: {
                    Image(systemName: "plus")
                        .font(.system(size: compact ? 11 : 13, weight: .semibold))
                        .frame(width: h, height: h)
                }
            }
            .foregroundStyle(Color.spOnAccent)
            .background(Color.spAccent, in: Capsule())
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Estados vacíos

struct EmptyCard: View {
    let title: String
    let message: String
    var buttonTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Text(title).font(.spHeadline).multilineTextAlignment(.center)
            Text(message).font(.spSub).foregroundStyle(Color.spSecondary).multilineTextAlignment(.center)
            if let buttonTitle, let action {
                Button(action: action) {
                    Text(buttonTitle)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.spInk)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .background(Color.spCardStrong, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(PressableStyle())
                .padding(.top, 4)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Color.spCard, in: RoundedRectangle(cornerRadius: SPRadius.card, style: .continuous))
    }
}

struct Toast: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
            Text(text).lineLimit(1)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(Color.spOnInk)
        .padding(.horizontal, 16)
        .frame(minHeight: 40)
        .background(Color.spInk, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
    }
}
