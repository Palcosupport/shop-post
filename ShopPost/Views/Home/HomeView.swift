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
    /// Ancho disponible para «Tus supermercados» (para repartir los círculos).
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
                    return FeedSlide(feed: feed, count: items.count, images: Array(items.lazy.compactMap(\.imageURL).prefix(4)))
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

    /// Nombre de la app centrado (el número de precios ya se ve en el catálogo).
    private var logo: some View {
        Text("Shop Post").font(.headline)
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
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { storesWidth = $0 }
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
    /// Fotos de la colección para el fondo difuminado de la portada.
    let images: [URL]
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

    /// Portada de la colección: fotos de sus productos difuminadas y teñidas con su color,
    /// y encima una placa de cristal con el título y el acceso.
    private func card(_ s: FeedSlide) -> some View {
        let color = s.feed.coverColor
        return NavigationLink(value: HomeRoute.feed(s.feed)) {
            // El fondo va detrás de un hueco de tamaño fijo: las fotos «fill» no pueden agrandar la tarjeta.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 200)
                .background { background(s, color) }
                .overlay(alignment: .leading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(s.count > 0 ? Count.items(s.count, "producto", "productos") : "Nada por ahora")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.spSecondary)
                    Text(s.feed.title)
                        .font(.title.bold())
                        .foregroundStyle(Color.spInk)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text("Ver \(s.feed.title.lowercased())")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.spOnInk)
                        .padding(.horizontal, 14).frame(minHeight: 32)
                        .background(Color.spInk, in: Capsule())
                        .padding(.top, 6)
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(16)
                }
            .clipShape(RoundedRectangle(cornerRadius: SPRadius.card, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    /// Fondo: hasta 4 fotos en columnas, muy difuminadas, con un velo del color de la colección.
    /// Sin fotos (colección vacía), un degradado de ese color.
    @ViewBuilder private func background(_ s: FeedSlide, _ color: Color) -> some View {
        if s.images.isEmpty {
            LinearGradient(colors: [color.mix(with: .white, by: 0.35), color.mix(with: .black, by: 0.1)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        } else {
            HStack(spacing: 0) {
                ForEach(s.images, id: \.self) { url in
                    Color.white
                        .overlay {
                            AsyncImage(url: url) { phase in
                                if let img = phase.image { img.resizable().scaledToFill() } else { Color.white }
                            }
                        }
                        .clipped()
                }
            }
            .background(Color.white)
            .compositingGroup()
            .blur(radius: 34, opaque: true)
            .overlay(color.opacity(0.38))
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

    /// Ancho mínimo de cada supermercado (círculo, aro y nombre).
    static let minWidth: CGFloat = 60

    /// Ancho de cada hueco: el ancho entero repartido si caben todos; si no, los que quepan más medio.
    /// `total` es el ancho de la pantalla; se descuentan los 16 pt de margen a cada lado.
    static func width(in total: CGFloat, count n: Int) -> CGFloat {
        let w = total - 32
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
