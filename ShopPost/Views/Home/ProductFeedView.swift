import SwiftUI

/// Ofertas, cambios de precio, novedades y favoritos.
struct ProductFeedView: View {
    @Environment(CatalogService.self) private var catalog
    @Environment(Preferences.self) private var prefs
    let feed: Feed
    @State private var store = "all"
    @State private var drops = true
    @State private var query = ""
    @State private var limit = 60
    @State private var sort: FeedSort = .relevance
    /// Borde inferior de las etiquetas y de la lista en pantalla: sirven para centrar el aviso de lista vacía.
    /// Se miden mientras se abre la pantalla y se fijan al terminar, para que luego el aviso se mueva con las etiquetas.
    @State private var chipsBottom: CGFloat = 0
    @State private var listBottom: CGFloat = 0
    @State private var measuring = true

    private var storeSet: Set<String>? {
        store == "all" ? Set(prefs.visibleStores(in: catalog).map(\.id)) : [store]
    }

    private var products: [Product] {
        var list: [Product]
        switch feed {
        case .offers: list = catalog.offers(stores: storeSet)
        case .changes: list = catalog.feedChanges(stores: storeSet, drops: drops)
        case .new: list = catalog.feedNew(stores: storeSet).map { catalog.byId[$0.id] ?? $0 }
        case .favorites: list = prefs.favorites.compactMap { catalog.byId[$0] }.filter { storeSet?.contains($0.store) ?? true }
        }
        let terms = Text2.normalize(query).split(separator: " ").map(String.init)
        if !terms.isEmpty { list = list.filter { p in terms.allSatisfy { p.key.contains($0) } } }
        return sort.apply(list)
    }

    var body: some View {
        let all = products
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 14) {
                    if feed == .changes {
                        ChipBar(items: [(true, "Bajadas", "↓"), (false, "Subidas", "↑")], selection: $drops)
                    }
                    if prefs.visibleStores(in: catalog).count > 1 {
                        ChipBar(items: [("all", "Todos", nil)] + prefs.visibleStores(in: catalog).map { ($0.id, $0.name, nil) },
                                selection: $store, brand: { BrandStyle.store($0) })
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { y in
                    if measuring { chipsBottom = y }
                }
                if all.isEmpty {
                    // Va dentro del contenido (no encima): se mueve a la vez que el buscador y las etiquetas, sin saltos.
                    VStack(spacing: 8) {
                        Text(emptyTitle).font(.spHeadline)
                        Text(emptyMessage).font(.spSub).foregroundStyle(Color.spSecondary)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    // Centrado en el hueco que queda bajo las etiquetas. El alto se toma al abrir la pantalla
                    // y no cambia después: así el aviso se mueve junto a las etiquetas, sin recolocarse.
                    .frame(maxWidth: .infinity)
                    .frame(height: max(160, listBottom - Self.bottomInset - chipsBottom - 14))
                } else {
                    ProductCollection(products: Array(all.prefix(limit)), grid: prefs.gridView, showStore: store == "all")
                    if all.count > limit {
                        PrimaryButton(title: "Ver más", style: .soft) { limit += 60 }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, Self.topGap)
            .padding(.bottom, tabBarClearance)
        }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { y in
            if measuring { listBottom = y }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(600))
            measuring = false
        }
        .scrollDismissesKeyboard(.immediately)
        .spScreen()
        .navigationTitle(feed.title)
        .navigationSubtitle(Count.items(all.count, "producto", "productos"))
        // Buscador nativo bajo el título: se esconde al desplazar, como en WhatsApp.
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Buscar en \(feed.title.lowercased())")
        // Pantalla de detalle: sin barra de pestañas, para dejar todo el alto a los productos.
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            // Filtro: cómo se ve la lista y en qué orden.
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Vista", selection: Bindable(prefs).gridView) {
                        Label("Cuadrícula", systemImage: "square.grid.2x2").tag(true)
                        Label("Lista", systemImage: "list.bullet").tag(false)
                    }
                    .pickerStyle(.inline)
                    Picker("Ordenar por", selection: $sort.animation(.snappy)) {
                        ForEach(FeedSort.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    // Mismo tamaño que el filtro de la app Teléfono.
                    // La barra ignora .font en los iconos: el símbolo va ya configurado a su tamaño.
                    Image(uiImage: UIImage(systemName: "line.3.horizontal.decrease",
                                           withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)) ?? UIImage())
                        .renderingMode(.template)
                }
                .accessibilityLabel("Filtrar y ordenar")
            }
        }
    }

    /// Aire entre los botones (o el buscador) y las etiquetas.
    private static let topGap: CGFloat = 10
    /// Zona de la barrita de inicio, que no cuenta para centrar.
    private static var bottomInset: CGFloat {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.safeAreaInsets.bottom ?? 34
    }

    private var emptyTitle: String {
        switch feed {
        case .favorites: "Aún no tienes favoritos"
        case .changes: drops ? "Sin bajadas recientes" : "Sin subidas recientes"
        default: "Nada por aquí"
        }
    }

    private var emptyMessage: String {
        switch feed {
        case .favorites: "Mantén pulsado un producto o toca la estrella en su ficha para guardarlo aquí."
        case .changes: "Los cambios aparecen cuando el servidor compara los precios de un día con el anterior."
        case .new: "Aquí verás los productos que los supermercados añadan a su catálogo."
        case .offers: "No hay ofertas para estos supermercados ahora mismo."
        }
    }
}

/// Orden de los productos en las listas de Ofertas, Cambios, Novedades y Favoritos.
enum FeedSort: String, CaseIterable, Identifiable {
    case relevance, priceAsc, priceDesc, unitPrice, discount, name
    var id: String { rawValue }

    var title: String {
        switch self {
        case .relevance: "Relevancia"
        case .priceAsc: "Precio: de menor a mayor"
        case .priceDesc: "Precio: de mayor a menor"
        case .unitPrice: "Precio por kilo o litro"
        case .discount: "Mayor descuento"
        case .name: "Nombre (A–Z)"
        }
    }

    var icon: String {
        switch self {
        case .relevance: "sparkles"
        case .priceAsc: "arrow.up"
        case .priceDesc: "arrow.down"
        case .unitPrice: "scalemass"
        case .discount: "percent"
        case .name: "textformat"
        }
    }

    /// «Relevancia» deja el orden en que llega cada lista (el que ya tenía).
    func apply(_ list: [Product]) -> [Product] {
        switch self {
        case .relevance: list
        case .priceAsc: list.sorted { $0.price < $1.price }
        case .priceDesc: list.sorted { $0.price > $1.price }
        // Los que no tienen precio por unidad van al final.
        case .unitPrice: list.sorted { ($0.unitPrice ?? .infinity) < ($1.unitPrice ?? .infinity) }
        case .discount: list.sorted { Self.discount($0) > Self.discount($1) }
        case .name: list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    /// Descuento en tanto por uno: precio tachado frente al actual (0 si no tiene).
    private static func discount(_ p: Product) -> Double {
        guard let old = p.strikePrice, old > 0 else { return 0 }
        return (old - p.price) / old
    }
}

struct SearchField: View {
    @Binding var text: String
    var prompt = "Buscar productos…"
    var focused: FocusState<Bool>.Binding? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.body).foregroundStyle(Color.spSecondary)
            field
                .font(.body)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.spTertiary)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 38)
        .background(Color.spChip, in: Capsule())
    }

    @ViewBuilder private var field: some View {
        if let focused {
            TextField(prompt, text: $text).focused(focused)
        } else {
            TextField(prompt, text: $text)
        }
    }
}
