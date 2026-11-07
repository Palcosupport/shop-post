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
        return list
    }

    var body: some View {
        let all = products
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ScreenTitle(title: feed.title, subtitle: Count.items(all.count, "producto", "productos"))
                SearchField(text: $query, prompt: "Buscar en \(feed.title.lowercased())…")
                if feed == .changes {
                    ChipBar(items: [(true, "Bajadas", "↓"), (false, "Subidas", "↑")], selection: $drops)
                }
                if prefs.visibleStores(in: catalog).count > 1 {
                    ChipBar(items: [("all", "Todos", nil)] + prefs.visibleStores(in: catalog).map { ($0.id, $0.name, nil) },
                            selection: $store)
                }
                if all.isEmpty {
                    EmptyCard(title: emptyTitle, message: emptyMessage)
                } else {
                    ProductCollection(products: Array(all.prefix(limit)), grid: prefs.gridView, showStore: store == "all")
                    if all.count > limit {
                        PrimaryButton(title: "Ver más", style: .soft) { limit += 60 }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, tabBarClearance)
        }
        .scrollDismissesKeyboard(.immediately)
        .spScreen()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { prefs.gridView.toggle() } label: {
                    Image(systemName: prefs.gridView ? "list.bullet" : "square.grid.2x2")
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
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

struct SearchField: View {
    @Binding var text: String
    var prompt = "Buscar productos…"
    var focused: FocusState<Bool>.Binding? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.system(size: 20)).foregroundStyle(Color.spSecondary)
            field
                .font(.system(size: 17))
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.spTertiary)
                }
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
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
