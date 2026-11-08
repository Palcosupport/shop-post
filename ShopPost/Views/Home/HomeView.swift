import SwiftUI

enum Feed: String, Hashable, CaseIterable {
    case offers, changes, new, favorites

    /// Tres tonos (oscuro, medio, claro) de la portada de la colección en el carrusel de Inicio.
    var coverPalette: (deep: Color, mid: Color, light: Color) {
        func rgb(_ v: UInt32) -> Color {
            Color(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
        }
        return switch self {
        case .new: (rgb(0x1A1C8C), rgb(0x4B47E0), rgb(0x3FC1F2))
        case .offers: (rgb(0xB80F2B), rgb(0xFF5A36), rgb(0xFFC24D))
        case .changes: (rgb(0x0A5E35), rgb(0x22B566), rgb(0xC4F26A))
        case .favorites: (rgb(0x8A5A00), rgb(0xF5B400), rgb(0xFFE27A))
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
    /// Ancho útil de «Tus supermercados» (para repartir los círculos).
    @State private var storesWidth: CGFloat = 370

    private var storeSet: Set<String>? {
        storeFilter == "all" ? Set(prefs.visibleStores(in: catalog).map(\.id)) : [storeFilter]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                greetingHeader
                missingCard
                FeedCarousel(slides: Feed.circles.map { feed in
                    let items = preview(feed)
                    return FeedSlide(feed: feed, count: items.count)
                })
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

    private var todayText: String {
        let s = Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "es_ES")))
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 6 ? "Buenas noches" : h < 14 ? "Buenos días" : h < 21 ? "Buenas tardes" : "Buenas noches"
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

    /// Logotipo centrado: «SHOP POST» en Futura, mayúsculas espaciadas (estilo G).
    private var logo: some View {
        Text("SHOP POST")
            .font(.custom("Futura-Bold", size: 17, relativeTo: .headline))
            .tracking(1.6)
            .foregroundStyle(Color.spInk)
            .accessibilityLabel("Shop Post")
            .accessibilityAddTraits(.isHeader)
    }

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(greeting)\(prefs.userName.isEmpty ? "" : ", \(prefs.userName)")")
                .font(.spTitle)
                .foregroundStyle(Color.spInk)
            // La fecha de hoy, como en Apple News («Sábado, 8 de noviembre»).
            Text(todayText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.spSecondary)
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
                    // El título ocupa justo el ancho útil: de ahí se saca el tamaño de los círculos.
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { storesWidth = $0 }
                // Si caben todos, se reparte el ancho entero; si no, se ve medio supermercado más (como en iOS).
                // «Todos» y «Favoritos» van delante de los supermercados.
                let item = StoreCircle.width(in: storesWidth, count: stores.count + 2)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 0) {
                        Button { select("all") } label: {
                            StoreCircle(storeId: nil, icon: "square.grid.2x2", title: "Todos", selected: storeFilter == "all", width: item)
                        }
                        .buttonStyle(PressableStyle())
                        NavigationLink(value: HomeRoute.feed(.favorites)) {
                            StoreCircle(storeId: nil, icon: "star", title: "Favoritos", selected: false, width: item)
                        }
                        .buttonStyle(PressableStyle())
                        ForEach(stores, id: \.id) { st in
                            Button { select(st.id) } label: {
                                StoreCircle(storeId: st.id, title: st.name, selected: storeFilter == st.id, width: item)
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, 16, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
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
            .scrollClipDisabled() // la sombra de las tarjetas no se corta en los bordes
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

    /// Portada de la colección al estilo de Apple Music: título grande en el centro,
    /// el número de productos abajo a la izquierda y «Ver …» abajo a la derecha. Toda la tarjeta se toca.
    private func card(_ s: FeedSlide) -> some View {
        NavigationLink(value: HomeRoute.feed(s.feed)) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .background { CoverBackground(feed: s.feed) }
                .overlay {
                    Text(s.feed.title)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .padding(.horizontal, 20)
                }
                .overlay {
                    VStack {
                        HStack {
                            Spacer()
                            Text("SHOP POST").font(.custom("Futura-Bold", size: 11, relativeTo: .caption2)).tracking(1.2)
                                .accessibilityHidden(true)
                        }
                        Spacer()
                        HStack(alignment: .firstTextBaseline) {
                            Text(s.count > 0 ? Count.items(s.count, "producto", "productos") : "Nada por ahora")
                                .font(.footnote.weight(.medium)).opacity(0.85)
                            Spacer(minLength: 8)
                            Text("Ver \(s.feed.title.lowercased())").font(.footnote.bold())
                        }
                    }
                    .padding(16)
                }
                .foregroundStyle(Color.spInk)
                .clipShape(RoundedRectangle(cornerRadius: SPRadius.card, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
        }
        .buttonStyle(PressableStyle())
    }
}

/// Fondo vivo de la portada: en modo claro, malla pastel sobre blanco; en oscuro, negro con halos de luz.
/// Los colores se desplazan despacio (se para si el usuario reduce el movimiento).
struct CoverBackground: View {
    let feed: Feed
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            if scheme == .dark { halos(t) } else { pastel(t) }
        }
    }

    private func pastel(_ t: Double) -> some View {
        let c = feed.coverPalette
        let cx = Float(0.5 + 0.18 * sin(t * 0.35)), cy = Float(0.5 + 0.14 * cos(t * 0.27))
        let top = Float(0.5 + 0.12 * sin(t * 0.22)), bottom = Float(0.5 + 0.12 * cos(t * 0.31))
        return MeshGradient(width: 3, height: 3, points: [
            [0, 0], [top, 0], [1, 0],
            [0, Float(0.5 + 0.1 * cos(t * 0.29))], [cx, cy], [1, Float(0.5 + 0.1 * sin(t * 0.33))],
            [0, 1], [bottom, 1], [1, 1],
        ], colors: [
            .white, c.light.opacity(0.45), .white,
            c.mid.opacity(0.35), .white, c.light.opacity(0.5),
            .white, c.mid.opacity(0.3), .white,
        ])
        .background(.white)
    }

    private func halos(_ t: Double) -> some View {
        let c = feed.coverPalette
        return GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Color.black
                Circle().fill(c.mid).frame(width: w * 0.7).blur(radius: 60)
                    .offset(x: w * (-0.2 + 0.08 * sin(t * 0.3)), y: h * (0.3 + 0.1 * cos(t * 0.25)))
                Circle().fill(c.light).frame(width: w * 0.45).blur(radius: 50)
                    .offset(x: w * (0.3 + 0.08 * cos(t * 0.27)), y: h * (-0.25 + 0.1 * sin(t * 0.33)))
            }
            .frame(width: w, height: h)
        }
    }
}

/// Supermercado en círculo (con su color de marca); el elegido lleva un aro alrededor.
struct StoreCircle: View {
    let storeId: String?
    /// Icono para los círculos que no son un supermercado (Todos, Favoritos).
    var icon: String = "square.grid.2x2"
    let title: String
    let selected: Bool
    /// Hueco que ocupa (lo calcula `width(in:count:)`).
    var width: CGFloat = 74

    /// Ancho mínimo de cada supermercado: tamaño cómodo; si no caben todos, el resto se ve deslizando.
    static let minWidth: CGFloat = 80

    /// Ancho de cada hueco: el ancho entero repartido si caben todos; si no, los que quepan más medio.
    /// `w` es el ancho útil (la pantalla sin los márgenes).
    static func width(in w: CGFloat, count n: Int) -> CGFloat {
        if CGFloat(n) * minWidth <= w { return w / CGFloat(n) }
        let shown = max(1, (w / minWidth - 0.5).rounded(.down))
        return w / (shown + 0.5)
    }

    var body: some View {
        VStack(spacing: 7) {
            // El círculo crece con el hueco (proporcional al ancho del dispositivo), con un tope.
            circle(diameter)
                .padding(4)
                .overlay(Circle().strokeBorder(selected ? ring : .clear, lineWidth: 2.5))
            Text(title)
                .font(.caption.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.spInk : Color.spSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: width)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var diameter: CGFloat { min(max(width - 22, 44), 64) }

    @ViewBuilder private func circle(_ d: CGFloat) -> some View {
        if let storeId {
            StoreBadge(storeId: storeId, size: d)
        } else {
            Image(systemName: icon)
                .font(.system(size: d * 0.4, weight: .medium))
                .foregroundStyle(Color.spInk)
                .frame(width: d, height: d)
                .background(Color.spChip, in: Circle())
        }
    }

    private var ring: Color { BrandStyle.store(storeId)?.background ?? .spInk }
}
