import SwiftUI

struct ProductDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ShopModel.self) private var shop
    @Environment(CatalogService.self) private var catalog
    @Environment(Preferences.self) private var prefs
    let product: Product
    @State private var quantity = 1
    @State private var alternatives: [Product]?
    @State private var facts: FoodFacts?
    @State private var showAlert = false

    private var current: Product { catalog.byId[product.id] ?? product }

    var body: some View {
        let p = current
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ZStack(alignment: .topLeading) {
                    ProductImage(url: p.imageURL, padding: 24, placeholderEmoji: catalog.category(p.cat)?.emoji ?? "🛒")
                        .frame(maxWidth: .infinity)
                        .frame(height: 240)
                        .background(Color.spCard, in: RoundedRectangle(cornerRadius: SPRadius.card, style: .continuous))
                    HStack(spacing: 6) {
                        if let promo = p.promo { Badge(text: promo, icon: "tag.fill") }
                        else if p.isOnOffer { Badge(text: "Oferta", icon: "tag.fill") }
                        if let pct = p.changePercent, abs(pct) >= 1 {
                            Badge(text: Money.percent(pct), color: pct < 0 ? .spGreen : .spRed, soft: pct < 0 ? .spGreenSoft : .spRedSoft,
                                  icon: pct < 0 ? "arrow.down" : "arrow.up")
                        }
                    }
                    .padding(14)
                }

                VStack(alignment: .leading, spacing: 6) {
                    StoreName(storeId: p.store)
                    Text(p.name).font(.spTitle).fixedSize(horizontal: false, vertical: true)
                    Text([p.brand, p.size].compactMap { $0 }.joined(separator: " · "))
                        .font(.spSub).foregroundStyle(Color.spSecondary)
                }

                HStack(alignment: .firstTextBaseline) {
                    PriceLabel(price: p.price, strike: p.strikePrice, size: 28)
                    Spacer()
                    if let u = Money.unitString(p.unitPrice, unit: p.unit) {
                        Text(u).font(.spSub).foregroundStyle(Color.spSecondary)
                    }
                }
                if let change = changeText(p) {
                    Text(change).font(.spSub).foregroundStyle(Color.spSecondary)
                }

                HStack(spacing: 12) {
                    actionTile(prefs.isFavorite(p.id) ? "star.fill" : "star", prefs.isFavorite(p.id) ? "Favorito" : "Favorito") {
                        prefs.toggleFavorite(p.id); Haptics.tap()
                    }
                    actionTile("bell", "Avísame") { showAlert = true }
                    actionTile("cabinet", "Despensa") {
                        shop.addToPantry(name: p.name, product: p, quantity: 1, place: p.cat == "congelados" ? "congelador" : "despensa", shelf: nil)
                    }
                    if let url = p.webURL {
                        Link(destination: url) { tileLabel("safari", "Web") }.buttonStyle(PressableStyle())
                    }
                }

                alternativesSection(p)
                factsSection
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .spScreen()
        .navigationTitle("Producto")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: { Image(systemName: "xmark") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: "\(p.name) — \(Money.string(p.price)) en \(catalog.store(p.store)?.name ?? p.store)\(p.url.map { "\n\($0)" } ?? "")") {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .safeAreaInset(edge: .bottom) { bottomBar(p) }
        .sheet(isPresented: $showAlert) { NavigationStack { AlertEditor(product: p) }.spSheet() }
        .task(id: p.id) {
            let found = await catalog.alternatives(to: p)
            alternatives = found
            if let ean = p.ean { facts = await OpenFoodFacts.lookup(ean: ean) }
        }
        .onAppear { quantity = max(1, shop.quantity(of: p.id)) }
    }

    private func changeText(_ p: Product) -> String? {
        guard let last = p.lastPrice ?? p.oldPrice, last != p.price, let d = (p.changedAt ?? p.date).flatMap(Day.parse) else { return nil }
        let verb = p.price < last ? "Bajó" : "Subió"
        return "\(verb) desde \(Money.string(last)) · \(Day.relative(d))"
    }

    private func tileLabel(_ icon: String, _ title: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.title3)
            Text(title).font(.footnote.weight(.medium))
        }
        .foregroundStyle(Color.spInk)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 58)
        .background(Color.spCard, in: RoundedRectangle(cornerRadius: SPRadius.tile, style: .continuous))
    }

    private func actionTile(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { tileLabel(icon, title) }.buttonStyle(PressableStyle())
    }

    @ViewBuilder private func alternativesSection(_ p: Product) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Más económicos", subtitle: "Productos parecidos en tus supermercados")
            if let alternatives {
                let cheaper = alternatives.filter { Matching.comparablePrice($0, like: p) < Matching.comparablePrice(p, like: p) }
                if cheaper.isEmpty {
                    Text(alternatives.isEmpty ? "No hemos encontrado productos parecidos." : "Es la opción más económica que hemos encontrado.")
                        .font(.spSub).foregroundStyle(Color.spSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .spCard(padding: 18)
                } else {
                    VStack(spacing: 10) {
                        ForEach(cheaper.prefix(8)) { alt in
                            Button { shop.presentedProduct = nil; Task { try? await Task.sleep(for: .milliseconds(350)); shop.presentedProduct = alt } } label: {
                                HStack(spacing: 12) {
                                    Thumb(url: alt.imageURL, size: 60)
                                    VStack(alignment: .leading, spacing: 4) {
                                        StoreName(storeId: alt.store)
                                        Text(alt.name).font(.subheadline.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                                        Badge(text: "Más económico", color: .spGreen, soft: .spGreenSoft, icon: "arrow.down")
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(Money.string(alt.price)).font(.spHeadline)
                                        if let u = Money.unitString(alt.unitPrice, unit: alt.unit) {
                                            Text(u).font(.spCaption).foregroundStyle(Color.spSecondary)
                                        }
                                    }
                                }
                                .foregroundStyle(Color.spInk)
                                .padding(12)
                                .background(Color.spCard, in: RoundedRectangle(cornerRadius: SPRadius.tile, style: .continuous))
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity).padding()
            }
        }
    }

    @ViewBuilder private var factsSection: some View {
        if let facts {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Información", subtitle: "Datos de Open Food Facts")
                VStack(alignment: .leading, spacing: 14) {
                    if let n = facts.nutriscore {
                        HStack {
                            Text("Nutri-Score").font(.spHeadline)
                            Spacer()
                            HStack(spacing: 3) {
                                ForEach(["a", "b", "c", "d", "e"], id: \.self) { g in
                                    Text(g.uppercased())
                                        .font(.system(size: g == n ? 17 : 13, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: g == n ? 34 : 24, height: g == n ? 34 : 24)
                                        .background(nutriColor(g).opacity(g == n ? 1 : 0.45), in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }
                    if let nova = facts.novaGroup {
                        HStack { Text("Procesado (NOVA)").font(.spHeadline); Spacer(); Text("\(nova) de 4").font(.spSub).foregroundStyle(Color.spSecondary) }
                    }
                    if !facts.displayNutrients.isEmpty {
                        VStack(spacing: 8) {
                            HStack { Text("Por 100 g / ml").font(.spCaption).foregroundStyle(Color.spSecondary); Spacer() }
                            ForEach(facts.displayNutrients, id: \.0) { row in
                                HStack { Text(row.0).font(.spSub); Spacer(); Text(row.1).font(.spSub.weight(.medium)) }
                            }
                        }
                    }
                    if let ing = facts.ingredients, !ing.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Ingredientes").font(.spHeadline)
                            Text(ing).font(.spSub).foregroundStyle(Color.spSecondary)
                        }
                    }
                }
                .spCard(padding: 20)
            }
        }
    }

    private func nutriColor(_ g: String) -> Color {
        switch g {
        case "a": Color(hex: 0x038141)
        case "b": Color(hex: 0x85BB2F)
        case "c": Color(hex: 0xE6A700)
        case "d": Color(hex: 0xEE8100)
        default: Color(hex: 0xE63E11)
        }
    }

    private func bottomBar(_ p: Product) -> some View {
        let inBasket = shop.quantity(of: p.id)
        return HStack(spacing: 12) {
            HStack(spacing: 0) {
                Button { quantity = max(1, quantity - 1) } label: { Image(systemName: "minus").frame(width: 40, height: 50) }
                Text("\(quantity)").font(.title3.weight(.semibold)).monospacedDigit().frame(minWidth: 24)
                Button { quantity += 1 } label: { Image(systemName: "plus").frame(width: 40, height: 50) }
            }
            .foregroundStyle(Color.spInk)
            .background(Color.spChip, in: Capsule())
            PrimaryButton(title: inBasket > 0 ? "Actualizar cesta (\(inBasket))" : "Añadir a la cesta", systemName: "basket") {
                shop.setQuantity(p, inBasket > 0 ? quantity : quantity)
                shop.show(inBasket > 0 ? "Cantidad actualizada" : "Añadido a \(shop.activeGroup?.title ?? "la cesta")")
                dismiss()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(Color.spBackground.opacity(0.96).ignoresSafeArea())
    }
}
