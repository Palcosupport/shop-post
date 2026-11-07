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
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .spScreen()
        .navigationTitle("\(greeting)\(prefs.userName.isEmpty ? "" : ", \(prefs.userName)")")
        .navigationSubtitle(updatedText)
        .toolbar {
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
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center, spacing: 12) {
                            Text(g.icon).font(.title2)
                                .frame(width: 44, height: 44)
                                .background(Color.spSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 1) {
                                Text("CESTA ACTIVA").font(.caption2.weight(.medium)).tracking(1.2)
                                    .foregroundStyle(Color.spSecondary)
                                Text(g.title).font(.headline)
                            }
                            Spacer()
                            Text("\(done)/\(items.count)").font(.headline).monospacedDigit()
                        }
                        ProgressLine(value: items.isEmpty ? 0 : Double(done) / Double(items.count))
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(items.count - done == 0 ? "¡Todo recogido!" : "Quedan \(Count.items(items.count - done))")
                                    .font(.spSub).foregroundStyle(Color.spSecondary)
                                Text(Money.string(g.total)).font(.spHeadline)
                            }
                            Spacer()
                            HStack(spacing: 4) {
                                Text("Ver cesta")
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                            }
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .frame(minHeight: 32)
                            .background(Color.spCardStrong, in: Capsule())
                        }
                    }
                    .foregroundStyle(Color.spInk)
                    .spCard(padding: 16)
                }
                .buttonStyle(PressableStyle())
            }
        }
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
                    .foregroundStyle(Color.spOnInk)
                    .padding(.horizontal, 12).frame(minHeight: 30)
                    .background(Color.spInk, in: Capsule())
                    .buttonStyle(PressableStyle())
            }
            .spCard(padding: 14)
        }
    }

    // MARK: Explorar

    private var exploreSection: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                .padding(.horizontal, 16)
            }
            .scrollClipDisabled()
            .padding(.horizontal, -16)
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
                    Image(systemName: feed.icon).font(.title.weight(.light)).foregroundStyle(Color.spTertiary)
                } else {
                    HStack(spacing: -14) {
                        ForEach(Array(imgs.enumerated()), id: \.offset) { _, url in
                            ProductImage(url: url, padding: 3).frame(width: 48, height: 64)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 76)
            VStack(alignment: .leading, spacing: 3) {
                Text(feed.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(products.isEmpty ? "Nada por ahora" : Count.items(products.count, "producto", "productos"))
                    .font(.caption).foregroundStyle(Color.spSecondary)
            }
        }
        .foregroundStyle(Color.spInk)
        .padding(12)
        .frame(width: 150, height: 140, alignment: .topLeading)
        .background(Color.spCard, in: RoundedRectangle(cornerRadius: SPRadius.card, style: .continuous))
    }
}
