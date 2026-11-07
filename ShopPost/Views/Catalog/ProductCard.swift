import SwiftUI

/// Tarjeta de producto en cuadrícula (imagen grande sobre gris piedra).
struct ProductCard: View {
    @Environment(ShopModel.self) private var shop
    @Environment(CatalogService.self) private var catalog
    let product: Product
    var showStore = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { shop.presentedProduct = product } label: {
                ZStack(alignment: .topLeading) {
                    ProductImage(url: product.imageURL, padding: 12, placeholderEmoji: catalog.category(product.cat)?.emoji ?? "🛒")
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .background(Color.spCard, in: RoundedRectangle(cornerRadius: SPRadius.tile, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        if let badge = badgeText {
                            Badge(text: badge.0, color: badge.1, soft: badge.2)
                        }
                    }
                    .padding(8)
                    if showStore {
                        StoreBadge(storeId: product.store, size: 20)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .topTrailing)
                    }
                }
            }
            .buttonStyle(PressableStyle())

            VStack(alignment: .leading, spacing: 3) {
                Text(product.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2, reservesSpace: true)
                    .foregroundStyle(Color.spInk)
                Text(product.subtitle.isEmpty ? (product.brand ?? " ") : product.subtitle)
                    .font(.caption).foregroundStyle(Color.spSecondary).lineLimit(1)
            }
            .padding(.horizontal, 2)
            .onTapGesture { shop.presentedProduct = product }

            HStack(alignment: .center) {
                PriceLabel(price: product.price, strike: product.strikePrice, size: 15)
                Spacer(minLength: 4)
                QuantityControl(quantity: shop.quantity(of: product.id), compact: true) { shop.setQuantity(product, $0) }
            }
            .padding(.horizontal, 2)
        }
        .contextMenu { ProductMenu(product: product) }
    }

    private var badgeText: (String, Color, Color)? {
        if let pct = product.changePercent, pct <= -1 { return (Money.percent(pct), .spGreen, .spGreenSoft) }
        if let promo = product.promo { return (promo, .spRed, .spRedSoft) }
        if product.isOnOffer { return ("Oferta", .spRed, .spRedSoft) }
        if let pct = product.changePercent, pct >= 1 { return (Money.percent(pct), .spRed, .spRedSoft) }
        return nil
    }
}

/// Fila de producto para vista de lista.
struct ProductRow: View {
    @Environment(ShopModel.self) private var shop
    @Environment(CatalogService.self) private var catalog
    let product: Product
    var showStore = false

    var body: some View {
        HStack(spacing: 12) {
            Thumb(url: product.imageURL, size: 56, emoji: catalog.category(product.cat)?.emoji ?? "🛒")
            VStack(alignment: .leading, spacing: 2) {
                if showStore { StoreName(storeId: product.store) }
                Text(product.name).font(.subheadline.weight(.medium)).lineLimit(2)
                PriceLabel(price: product.price, strike: product.strikePrice, size: 15)
                if !product.subtitle.isEmpty {
                    Text(product.subtitle).font(.spCaption).foregroundStyle(Color.spSecondary).lineLimit(1)
                }
                if let promo = product.promo { Badge(text: promo) }
            }
            Spacer(minLength: 6)
            QuantityControl(quantity: shop.quantity(of: product.id), compact: true) { shop.setQuantity(product, $0) }
        }
        .foregroundStyle(Color.spInk)
        .padding(10)
        .background(Color.spCard, in: RoundedRectangle(cornerRadius: SPRadius.tile, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { shop.presentedProduct = product }
        .contextMenu { ProductMenu(product: product) }
    }
}

struct ProductMenu: View {
    @Environment(ShopModel.self) private var shop
    @Environment(Preferences.self) private var prefs
    let product: Product

    var body: some View {
        Button { shop.add(product) } label: { Label("Añadir a la cesta", systemImage: "basket") }
        Button { prefs.toggleFavorite(product.id) } label: {
            Label(prefs.isFavorite(product.id) ? "Quitar de favoritos" : "Añadir a favoritos",
                  systemImage: prefs.isFavorite(product.id) ? "star.slash" : "star")
        }
        Button {
            shop.addToPantry(name: product.name, product: product, quantity: 1, place: product.cat == "congelados" ? "congelador" : "despensa", shelf: nil)
        } label: { Label("Guardar en la despensa", systemImage: "cabinet") }
        Button { shop.presentedProduct = product } label: { Label("Buscar más económicos", systemImage: "magnifyingglass") }
    }
}

/// Lista o cuadrícula de productos.
struct ProductCollection: View {
    let products: [Product]
    var grid = true
    var showStore = false

    var body: some View {
        if grid {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 16) {
                ForEach(products) { ProductCard(product: $0, showStore: showStore) }
            }
        } else {
            LazyVStack(spacing: 8) {
                ForEach(products) { ProductRow(product: $0, showStore: showStore) }
            }
        }
    }
}
