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
            VStack(alignment: .leading, spacing: 30) {
                header
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(greeting), \(prefs.userName.isEmpty ? "hola" : prefs.userName)")
                        .font(.spSub).foregroundStyle(Color.spSecondary)
                    Text("¿Qué necesitas hoy?").font(.spLargeTitle)
                }
                if prefs.visibleStores(in: catalog).count > 1 {
                    ChipBar(items: [("all", "Todos", nil)] + prefs.visibleStores(in: catalog).map { ($0.id, $0.name, nil) },
                            selection: $storeFilter)
                }
                basketCard
                missingCard
                exploreSection
                dropsSection
                alertsRow
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .spScreen()
        .toolbarVisibility(.hidden, for: .navigationBar)
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

    // MARK: Cabecera

    private var header: some View {
        HStack(alignment: .center) {
            BrandHeader()
            Spacer()
            Button { showProfile = true } label: {
                HStack(spacing: 10) {
                    Group {
                        if catalog.state == .loading {
                            ProgressView()
                        } else {
                            Image(systemName: "storefront").font(.system(size: 22)).foregroundStyle(Color.spSecondary)
                        }
                    }
                    .frame(width: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Count.string(catalog.totalCount)).font(.system(size: 17, weight: .semibold))
                        Text(updatedText).font(.spCaption).foregroundStyle(Color.spSecondary)
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 64)
                .background(Color.spCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Perfil y supermercados")
        }
    }

    private var updatedText: String {
        if catalog.state == .loading { return "actualizando" }
        guard let d = catalog.lastUpdate else { return "productos" }
        return "precios de \(Day.relative(d))"
    }

    // MARK: Cesta activa

    @ViewBuilder private var basketCard: some View {
        let _ = shop.revision
        if let g = shop.activeGroup {
            let items = g.itemList
            let done = items.filter(\.checked).count
            if items.isEmpty {
                EmptyCard(title: "Tu cesta «\(g.title)» está vacía",
                          message: "Busca productos en el catálogo o escanea un código de barras para empezar tu lista.",
                          buttonTitle: "Explorar el catálogo") { shop.tab = .catalog }
            } else {
                Button { shop.tab = .basket } label: {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top) {
                            Text(g.icon).font(.system(size: 34))
                                .frame(width: 60, height: 60)
                                .background(Color.spSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("CESTA ACTIVA").font(.system(size: 12, weight: .medium)).tracking(2)
                                    .foregroundStyle(Color.spSecondary)
                                Text(g.title).font(.spTitle)
                            }
                            Spacer()
                            Text("\(done)/\(items.count)").font(.system(size: 22, weight: .semibold)).monospacedDigit()
                        }
                        ProgressLine(value: items.isEmpty ? 0 : Double(done) / Double(items.count))
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(items.count - done == 0 ? "¡Todo recogido!" : "Quedan \(Count.items(items.count - done))")
                                    .font(.spSub).foregroundStyle(Color.spSecondary)
                                Text(Money.string(g.total)).font(.spHeadline)
                            }
                            Spacer()
                            HStack(spacing: 6) {
                                Text("Ver cesta")
                                Image(systemName: "arrow.right")
                            }
                            .font(.system(size: 16, weight: .medium))
                            .padding(.horizontal, 18)
                            .frame(height: 46)
                            .background(Color.spCardStrong, in: Capsule())
                        }
                    }
                    .foregroundStyle(Color.spInk)
                    .spCard(padding: 22, radius: 30)
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    @ViewBuilder private var missingCard: some View {
        let missing = shop.missingPantry(in: shop.activeGroup)
        if !missing.isEmpty {
            HStack(spacing: 14) {
                Image(systemName: "exclamationmark.circle").font(.system(size: 22))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Falta en casa: \(Count.items(missing.count, "producto", "productos"))").font(.spHeadline)
                    Text(missing.prefix(3).compactMap(\.name).joined(separator: ", ")).font(.spCaption)
                        .foregroundStyle(Color.spSecondary).lineLimit(1)
                }
                Spacer()
                Button("Añadir") { shop.moveMissingToBasket(missing) }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.spOnInk)
                    .padding(.horizontal, 16).frame(height: 38)
                    .background(Color.spInk, in: Capsule())
                    .buttonStyle(PressableStyle())
            }
            .spCard(padding: 18)
        }
    }

    // MARK: Explorar

    private var exploreSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Ahorra hoy")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Feed.allCases, id: \.self) { feed in
                        NavigationLink(value: HomeRoute.feed(feed)) {
                            FeedCard(feed: feed, products: preview(feed))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollClipDisabled()
            .padding(.horizontal, -20)
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
            VStack(alignment: .leading, spacing: 14) {
                SectionLinkHeader(title: "Han bajado", subtitle: "Últimos 14 días", value: HomeRoute.feed(.changes))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(drops) { p in
                            ProductCard(product: catalog.byId[p.id] ?? p, showStore: true).frame(width: 168)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .scrollClipDisabled()
                .padding(.horizontal, -20)
            }
        }
    }

    private var alertsRow: some View {
        let active = prefs.alerts.filter(\.enabled).count
        return VStack(spacing: 12) {
            NavigationLink(value: HomeRoute.alerts) {
                OptionRow(icon: "bell", title: active == 0 ? "Crea tu primera alerta de ahorro" : "Alertas de ahorro",
                          subtitle: active == 0 ? "Te avisamos cuando baje lo que te interesa" : "\(active) activas")
            }
            NavigationLink(value: HomeRoute.history) {
                OptionRow(icon: "clock.arrow.circlepath", title: "Compras anteriores",
                          subtitle: prefs.history.isEmpty ? "Repite una compra con un toque" : Count.items(prefs.history.count, "compra guardada", "compras guardadas"))
            }
        }
        .buttonStyle(PressableStyle())
    }
}

struct FeedCard: View {
    let feed: Feed
    let products: [Product]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                let imgs = products.prefix(3).compactMap(\.imageURL)
                if imgs.isEmpty {
                    Image(systemName: feed.icon).font(.system(size: 36, weight: .light)).foregroundStyle(Color.spTertiary)
                } else {
                    HStack(spacing: -18) {
                        ForEach(Array(imgs.enumerated()), id: \.offset) { _, url in
                            ProductImage(url: url, padding: 4).frame(width: 64, height: 84)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 118)
            VStack(alignment: .leading, spacing: 3) {
                Text(feed.title).font(.spHeadline).lineLimit(1)
                Text(products.isEmpty ? "Nada por ahora" : Count.items(products.count, "producto", "productos"))
                    .font(.spSub).foregroundStyle(Color.spSecondary)
            }
        }
        .foregroundStyle(Color.spInk)
        .padding(18)
        .frame(width: 196, height: 210, alignment: .topLeading)
        .background(Color.spCard, in: RoundedRectangle(cornerRadius: SPRadius.card, style: .continuous))
    }
}
