import SwiftUI

enum Feed: String, Hashable, CaseIterable {
    case offers, changes, new, favorites

    var title: String {
        switch self {
        case .offers: "Ofertas"
        case .changes: "Cambios de precio"
        case .new: "Novedades"
        case .favorites: "Favoritos"
        }
    }

    var icon: String {
        switch self {
        case .offers: "tag"
        case .changes: "chart.line.downtrend.xyaxis"
        case .new: "sparkles"
        case .favorites: "star"
        }
    }
}

enum HomeRoute: Hashable { case feed(Feed), alerts, history, profile }

struct HomeView: View {
    @Environment(ShopModel.self) private var shop
    @Environment(CatalogService.self) private var catalog
    @Environment(Preferences.self) private var prefs
    @State private var storeFilter = "all"
    @State private var showProfile = false

    private var storeSet: Set<String>? {
        storeFilter == "all" ? Set(prefs.visibleStores(in: catalog).map(\.id)) : [storeFilter]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                greetingHeader
                if prefs.visibleStores(in: catalog).count > 1 {
                    ChipBar(items: [("all", "Todos", nil)] + prefs.visibleStores(in: catalog).map { ($0.id, $0.name, nil) },
                            selection: $storeFilter, brand: { BrandStyle.store($0) })
                }
                missingCard
                heroCard
                exploreSection
                dropsSection
                mindfulBanner
                historyRow
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .spScreen()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { logo }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showProfile = true } label: {
                    if prefs.initials.isEmpty {
                        Image(systemName: "person.crop.circle")
                    } else {
                        Text(prefs.initials).font(.subheadline.weight(.semibold))
                    }
                }
                .accessibilityLabel("Perfil y supermercados")
            }
        }
        .refreshable { await catalog.refresh(force: false) }
        .navigationDestination(for: HomeRoute.self) { route in
            switch route {
            case .feed(let f): ProductFeedView(feed: f)
            case .alerts: AlertsView()
            case .history: HistoryView()
            case .profile: ProfileView()
            }
        }
        .sheet(isPresented: $showProfile) { NavigationStack { ProfileView() }.spSheet() }
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 6 ? "Buenas noches" : h < 14 ? "Buenos días" : h < 21 ? "Buenas tardes" : "Buenas noches"
    }

    private var updatedText: String {
        if catalog.state == .loading { return "Actualizando precios…" }
        guard let d = catalog.lastUpdate else { return "Shop Post" }
        return "\(Count.string(catalog.totalCount)) precios de \(Day.relative(d))"
    }

    @ViewBuilder private var missingCard: some View {
        let missing = shop.missingPantry(in: shop.activeGroup)
        if !missing.isEmpty {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.circle").font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Falta en casa: \(Count.items(missing.count, "producto", "productos"))").font(.spHeadline)
                    Text(missing.prefix(3).compactMap(\.name).joined(separator: ", ")).font(.spCaption)
                        .foregroundStyle(Color.spSecondary).lineLimit(1)
                }
                Spacer()
                Button("Añadir") { shop.moveMissingToBasket(missing) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.spOnAccent)
                    .padding(.horizontal, 12).frame(minHeight: 30)
                    .background(Color.spAccent, in: Capsule())
                    .buttonStyle(PressableStyle())
            }
            .spCard(padding: 14)
        }
    }

    // MARK: Cabecera

    /// Nombre de la app centrado, con la fecha de los precios debajo.
    private var logo: some View {
        VStack(spacing: 1) {
            Text("Shop Post").font(.headline)
            Text(updatedText).font(.caption2).foregroundStyle(Color.spSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(greeting)\(prefs.userName.isEmpty ? "" : ", \(prefs.userName)").")
                .font(.spTitle)
                .foregroundStyle(Color.spInk)
            Text("¿Qué te falta hoy?").font(.subheadline).foregroundStyle(Color.spSecondary)
        }
        .padding(.top, 8)
    }

    // MARK: Destacado

    /// El producto que más ha bajado (con foto); si no hay bajadas, la primera oferta.
    private var featured: (product: Product, drop: Double?)? {
        // La bajada se mide en el registro de cambios (pct); el producto del catálogo aporta foto y precio al día.
        let best = catalog.feedChanges(stores: storeSet, drops: true)
            .filter { $0.imageURL != nil }
            .min { ($0.pct ?? 0) < ($1.pct ?? 0) }
        if let best { return (catalog.byId[best.id] ?? best, best.pct) }
        return catalog.offers(stores: storeSet).first { $0.imageURL != nil }.map { ($0, nil) }
    }

    @ViewBuilder private var heroCard: some View {
        if let (p, drop) = featured {
            let pct = drop.flatMap { $0 <= -1 ? $0 : nil }
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    Badge(text: pct.map { "Ha bajado \(Money.percent($0))" } ?? "Oferta destacada",
                          color: pct == nil ? .spRed : .spGreen, soft: pct == nil ? .spRedSoft : .spGreenSoft)
                    Text(p.name)
                        .font(.spHeadline)
                        .foregroundStyle(Color.spInk)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    StoreName(storeId: p.store)
                    PriceLabel(price: p.price, strike: p.strikePrice, size: 17)
                    Button { shop.presentedProduct = p } label: {
                        Text("Ver oferta").font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.spOnAccent)
                            .padding(.horizontal, 14).frame(minHeight: 32)
                            .background(Color.spAccent, in: Capsule())
                    }
                    .buttonStyle(PressableStyle())
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ProductImage(url: p.imageURL, padding: 4)
                    .frame(width: 130, height: 160)
            }
            .spCard(padding: 18)
            .contentShape(Rectangle())
            .onTapGesture { shop.presentedProduct = p }
        }
    }

    // MARK: Explorar

    private var exploreSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Ahorra hoy", actionTitle: "Ver todo") { shop.tab = .catalog }
            HStack(alignment: .top, spacing: 8) {
                ForEach(Feed.allCases, id: \.self) { feed in
                    NavigationLink(value: HomeRoute.feed(feed)) {
                        FeedCircle(feed: feed, image: preview(feed).lazy.compactMap(\.imageURL).first)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
    }

    private func preview(_ feed: Feed) -> [Product] {
        switch feed {
        case .offers: catalog.offers(stores: storeSet)
        case .changes: catalog.feedChanges(stores: storeSet, drops: true)
        case .new: catalog.feedNew(stores: storeSet)
        case .favorites: prefs.favorites.compactMap { catalog.byId[$0] }
        }
    }

    @ViewBuilder private var dropsSection: some View {
        let drops = Array(catalog.feedChanges(stores: storeSet, drops: true).prefix(12))
        if !drops.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionLinkHeader(title: "Han bajado", subtitle: "Últimos 14 días", value: HomeRoute.feed(.changes))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(drops) { p in
                            ProductCard(product: catalog.byId[p.id] ?? p, showStore: true).frame(width: 140)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollClipDisabled()
                .padding(.horizontal, -16)
            }
        }
    }

    // MARK: Alertas e historial

    private var mindfulBanner: some View {
        let active = prefs.alerts.filter(\.enabled).count
        return NavigationLink(value: HomeRoute.alerts) {
            HStack(spacing: 18) {
                Image(systemName: "leaf")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Color.spSecondary)
                    .frame(width: 56)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Compra con cabeza.\nAhorra de verdad.")
                        .font(.spHeadline)
                        .foregroundStyle(Color.spInk)
                        .multilineTextAlignment(.leading)
                    HStack {
                        Text(active == 0 ? "Crea tu primera alerta de ahorro" : "Alertas de ahorro: \(active) activas")
                            .font(.footnote)
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote)
                    }
                    .foregroundStyle(Color.spSecondary)
                }
            }
            .spCard(padding: 18)
        }
        .buttonStyle(PressableStyle())
    }

    private var historyRow: some View {
        NavigationLink(value: HomeRoute.history) {
            OptionRow(icon: "clock.arrow.circlepath", title: "Compras anteriores",
                      subtitle: prefs.history.isEmpty ? "Repite una compra con un toque" : Count.items(prefs.history.count, "compra guardada", "compras guardadas"))
        }
        .buttonStyle(PressableStyle())
    }
}

/// Círculo con la foto de un producto y el nombre de la colección debajo.
struct FeedCircle: View {
    let feed: Feed
    let image: URL?

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(Color.spCard)
                if let image {
                    ProductImage(url: image, padding: 14)
                } else {
                    Image(systemName: feed.icon).font(.title2.weight(.light)).foregroundStyle(Color.spTertiary)
                }
            }
            .frame(width: 76, height: 76)
            .clipShape(Circle())
            Text(feed.title)
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center).lineLimit(2)
                .foregroundStyle(Color.spInk)
        }
        .frame(maxWidth: .infinity)
    }
}
