import SwiftUI

enum Feed: String, Hashable, CaseIterable {
    case offers, changes, new, favorites

    /// Color de la portada de la colección en el carrusel de Inicio.
    var coverColor: Color {
        switch self {
        case .new: Color(uiColor: .systemIndigo)
        case .offers: Color(uiColor: .systemRed)
        case .changes: Color(uiColor: .systemGreen)
        case .favorites: Color(uiColor: .systemYellow)
        }
    }

    /// Colecciones del carrusel de Inicio, en este orden (Favoritos va junto al saludo).
    static let circles: [Feed] = [.new, .offers, .changes]

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
                missingCard
                FeedCarousel(slides: Feed.circles.map { FeedSlide(feed: $0, count: preview($0).count) })
                storesSection
                highlightsSection
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

    /// Saludo con el acceso a Favoritos a la derecha, bajo el botón de perfil.
    private var greetingHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(greeting)\(prefs.userName.isEmpty ? "" : ", \(prefs.userName)").")
                    .font(.spTitle)
                    .foregroundStyle(Color.spInk)
                Text("¿Qué te falta hoy?").font(.subheadline).foregroundStyle(Color.spSecondary)
            }
            Spacer(minLength: 0)
            NavigationLink(value: HomeRoute.feed(.favorites)) {
                Image(systemName: "star")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(Color.spAccent)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Favoritos")
        }
        .padding(.top, 8)
    }

    // MARK: Carrusel

    // MARK: Destacados

    /// Lo mejor de cada colección: la mayor oferta, la mayor bajada y la última novedad (todas con foto).
    private var highlights: [Product] {
        var out: [Product] = []
        let offer = preview(.offers).filter { $0.imageURL != nil }.max { catalog.discount($0) < catalog.discount($1) }
        // La bajada se mide en el registro de cambios (pct); el catálogo aporta foto y precio al día.
        let drop = catalog.feedChanges(stores: storeSet, drops: true)
            .filter { $0.imageURL != nil }
            .min { ($0.pct ?? 0) < ($1.pct ?? 0) }
            .map { catalog.byId[$0.id] ?? $0 }
        let new = preview(.new).first { $0.imageURL != nil }
        for p in [offer, drop, new].compactMap({ $0 }) where !out.contains(where: { $0.id == p.id }) { out.append(p) }
        return out
    }

    @ViewBuilder private var highlightsSection: some View {
        let items = highlights
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Destacados de hoy")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(items) { ProductCard(product: $0, showStore: true).frame(width: 140) }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollClipDisabled()
                .padding(.horizontal, -16)
            }
        }
    }

    // MARK: Tus supermercados

    @ViewBuilder private var storesSection: some View {
        let stores = prefs.visibleStores(in: catalog)
        if stores.count > 1 {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Tus supermercados", actionTitle: "Ver todo") { shop.tab = .catalog }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        StoreCircle(storeId: nil, title: "Todos", selected: storeFilter == "all") { select("all") }
                        ForEach(stores, id: \.id) { st in
                            StoreCircle(storeId: st.id, title: st.name, selected: storeFilter == st.id) { select(st.id) }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollClipDisabled()
                .padding(.horizontal, -16)
            }
        }
    }

    private func select(_ id: String) {
        withAnimation(.snappy) { storeFilter = id }
        Haptics.tap()
    }

    private func preview(_ feed: Feed) -> [Product] {
        switch feed {
        case .offers: catalog.offers(stores: storeSet)
        case .changes: catalog.feedChanges(stores: storeSet, drops: true).map { catalog.byId[$0.id] ?? $0 }
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

struct FeedSlide {
    let feed: Feed
    let count: Int
}

/// Panel de Inicio: portadas de las colecciones al estilo de Apple TV (pasa solo y deja ver la siguiente).
struct FeedCarousel: View {
    let slides: [FeedSlide]
    @State private var page: Feed?

    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(slides, id: \.feed) { slide in
                        card(slide)
                            .containerRelativeFrame(.horizontal) { w, _ in w - 44 }
                            .scrollTransition(axis: .horizontal) { c, phase in
                                c.scaleEffect(phase.isIdentity ? 1 : 0.94).opacity(phase.isIdentity ? 1 : 0.6)
                            }
                            .id(slide.feed)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $page)
            .contentMargins(.horizontal, 22)
            .padding(.horizontal, -16)

            HStack(spacing: 7) {
                ForEach(slides, id: \.feed) { slide in
                    Capsule()
                        .fill(current == slide.feed ? Color.spInk : Color.spTertiary)
                        .frame(width: current == slide.feed ? 18 : 7, height: 7)
                        .onTapGesture { withAnimation(.snappy) { page = slide.feed } }
                }
            }
            .animation(.snappy, value: current)
            .accessibilityHidden(true)
        }
        .task(id: current) {
            // Avanza solo cada 6 s; al tocar o deslizar se reinicia la cuenta.
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, let i = slides.firstIndex(where: { $0.feed == current }) else { return }
            withAnimation(.smooth(duration: 0.6)) { page = slides[(i + 1) % slides.count].feed }
        }
    }

    private var current: Feed? { page ?? slides.first?.feed }

    /// Portada de la colección: color propio, icono grande de fondo, título y acceso.
    private func card(_ s: FeedSlide) -> some View {
        let color = s.feed.coverColor
        return NavigationLink(value: HomeRoute.feed(s.feed)) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [color.mix(with: .white, by: 0.12), color.mix(with: .black, by: 0.28)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: s.feed.icon)
                    .font(.system(size: 150, weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.22))
                    .rotationEffect(.degrees(-8))
                    .offset(x: 40, y: -10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                VStack(alignment: .leading, spacing: 6) {
                    Text(s.count > 0 ? Count.items(s.count, "producto", "productos") : "Nada por ahora")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Text(s.feed.title)
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text("Ver \(s.feed.title.lowercased())")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(color.mix(with: .black, by: 0.3))
                        .padding(.horizontal, 14).frame(minHeight: 32)
                        .background(.white, in: Capsule())
                        .padding(.top, 6)
                }
                .padding(20)
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: SPRadius.card, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

/// Supermercado en círculo (con su color de marca); el elegido lleva un aro alrededor.
struct StoreCircle: View {
    let storeId: String?
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Group {
                    if let storeId {
                        StoreBadge(storeId: storeId, size: 50)
                    } else {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Color.spInk)
                            .frame(width: 50, height: 50)
                            .background(Color.spChip, in: Circle())
                    }
                }
                .padding(4)
                .overlay(Circle().strokeBorder(selected ? ring : .clear, lineWidth: 2.5))
                Text(title)
                    .font(.caption.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.spInk : Color.spSecondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 62)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var ring: Color { BrandStyle.store(storeId)?.background ?? .spInk }
}
