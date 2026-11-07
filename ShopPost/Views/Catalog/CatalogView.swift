import SwiftUI

enum CatalogSort: String, CaseIterable, Identifiable {
    case relevance, priceUp, priceDown, unitUp, offers
    var id: String { rawValue }
    var title: String {
        switch self {
        case .relevance: "Relevancia"
        case .priceUp: "Precio: más barato"
        case .priceDown: "Precio: más caro"
        case .unitUp: "Precio por kg/L: más barato"
        case .offers: "Ofertas primero"
        }
    }
}

struct CatalogView: View {
    @Environment(ShopModel.self) private var shop
    @Environment(CatalogService.self) private var catalog
    @Environment(Preferences.self) private var prefs
    @State private var query = ""
    @State private var debounced = ""
    @State private var category = "all"
    @State private var sort: CatalogSort = .relevance
    @State private var storeID: String? = nil      // nil = todos tus supermercados
    @State private var showStores = false
    @State private var limit = 80
    @FocusState private var searchFocused: Bool

    private var storeSet: Set<String> {
        if let storeID { return [storeID] }
        return Set(prefs.visibleStores(in: catalog).map(\.id))
    }

    private var results: [Product] {
        var list = catalog.search(debounced, stores: storeSet, category: category == "all" ? nil : category,
                                  limit: debounced.isEmpty ? 100_000 : 2_000)
        switch sort {
        case .relevance: if debounced.isEmpty { list.sort { ($0.cat, $0.name) < ($1.cat, $1.name) } }
        case .priceUp: list.sort { $0.price < $1.price }
        case .priceDown: list.sort { $0.price > $1.price }
        case .unitUp: list.sort { ($0.unitPrice ?? .greatestFiniteMagnitude) < ($1.unitPrice ?? .greatestFiniteMagnitude) }
        case .offers: list.sort { ($0.isOnOffer ? 0 : 1, $0.price) < ($1.isOnOffer ? 0 : 1, $1.price) }
        }
        return list
    }

    private var categoriesWithProducts: [CategoryInfo] {
        let present = Set(catalog.productsByStore.filter { storeSet.contains($0.key) }.values.flatMap { $0.map(\.cat) })
        return catalog.categories.filter { present.contains($0.id) }
    }

    var body: some View {
        let list = results
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(count: list.count)
                HStack(spacing: 12) {
                    SearchField(text: $query, prompt: "Buscar productos…", focused: $searchFocused)
                    Menu {
                        Picker("Ordenar", selection: $sort) {
                            ForEach(CatalogSort.allCases) { Text($0.title).tag($0) }
                        }
                        Divider()
                        Button { prefs.gridView.toggle() } label: {
                            Label(prefs.gridView ? "Ver como lista" : "Ver como cuadrícula",
                                  systemImage: prefs.gridView ? "list.bullet" : "square.grid.2x2")
                        }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 20))
                            .foregroundStyle(sort == .relevance ? Color.spInk : Color.spOnInk)
                            .frame(width: 56, height: 56)
                            .background(sort == .relevance ? Color.spChip : Color.spInk, in: Circle())
                    }
                }
                ChipBar(items: [("all", "Todas", nil)] + categoriesWithProducts.map { ($0.id, $0.name, $0.emoji) },
                        selection: $category)

                content(list)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, tabBarClearance)
        }
        .scrollDismissesKeyboard(.immediately)
        .spScreen()
        .toolbarVisibility(.hidden, for: .navigationBar)
        .sheet(isPresented: $showStores) { StorePicker(selection: $storeID).spSheet() }
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(250))
            if !Task.isCancelled { debounced = query; limit = 80 }
        }
        .onChange(of: category) { limit = 80 }
        .onChange(of: storeID) { limit = 80 }
        .onAppear {
            if storeID == nil, let def = prefs.defaultStore, catalog.store(def) != nil { storeID = def }
            if shop.catalogFocusSearch { searchFocused = true; shop.catalogFocusSearch = false }
        }
        .onChange(of: shop.catalogFocusSearch) { _, v in if v { searchFocused = true; shop.catalogFocusSearch = false } }
    }

    private func header(count: Int) -> some View {
        HStack(alignment: .center) {
            ScreenTitle(title: "Catálogo",
                        subtitle: "\(storeID.flatMap { catalog.store($0)?.name } ?? "Todos tus supermercados") · \(Count.items(count, "producto", "productos"))")
            Button { showStores = true } label: {
                Group {
                    if let storeID {
                        StoreBadge(storeId: storeID, size: 60)
                    } else {
                        Image(systemName: "storefront")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.spOnInk)
                            .frame(width: 60, height: 60)
                            .background(Color.spInk, in: Circle())
                    }
                }
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Elegir supermercado")
        }
    }

    @ViewBuilder private func content(_ list: [Product]) -> some View {
        switch catalog.state {
        case .failed(let msg) where catalog.productsByStore.isEmpty:
            EmptyCard(title: "No se pudieron cargar los precios", message: msg, buttonTitle: "Reintentar") {
                Task { await catalog.refresh(force: true) }
            }
        case .loading where catalog.productsByStore.isEmpty, .idle where catalog.productsByStore.isEmpty:
            VStack(spacing: 12) {
                ProgressView()
                Text(catalog.progress.isEmpty ? "Cargando catálogo…" : catalog.progress)
                    .font(.spSub).foregroundStyle(Color.spSecondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 60)
        default:
            if list.isEmpty {
                EmptyCard(title: "Sin resultados",
                          message: debounced.isEmpty ? "No hay productos en esta categoría." : "Prueba con otra palabra o busca en todos tus supermercados.",
                          buttonTitle: storeID != nil ? "Buscar en todos" : nil) { storeID = nil }
            } else {
                ProductCollection(products: Array(list.prefix(limit)), grid: prefs.gridView, showStore: storeID == nil)
                if list.count > limit {
                    PrimaryButton(title: "Ver más (\(Count.string(list.count - limit)))", style: .soft) { limit += 80 }
                }
            }
        }
    }
}

/// Selector de supermercado (cuadrícula de tarjetas).
struct StorePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CatalogService.self) private var catalog
    @Environment(Preferences.self) private var prefs
    @Binding var selection: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("Elige supermercado").font(.spTitle)
                    Spacer()
                    CircleButton(systemName: "xmark", size: 44) { dismiss() }
                }
                Button {
                    selection = nil; dismiss()
                } label: {
                    OptionRow(icon: "square.grid.3x3", title: "Todos tus supermercados",
                              subtitle: "Busca y compara a la vez", circled: true)
                        .overlay(RoundedRectangle(cornerRadius: SPRadius.card).stroke(Color.spInk, lineWidth: selection == nil ? 2 : 0))
                }
                .buttonStyle(PressableStyle())
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    ForEach(catalog.stores) { s in
                        Button {
                            guard s.isAvailable else { return }
                            selection = s.id; dismiss()
                        } label: {
                            VStack(spacing: 10) {
                                StoreBadge(storeId: s.id, size: 52)
                                Text(s.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                                Text(s.isAvailable ? Count.string(s.count ?? 0) : "No disponible")
                                    .font(.system(size: 12)).foregroundStyle(Color.spSecondary)
                            }
                            .foregroundStyle(Color.spInk)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color.spCard, in: RoundedRectangle(cornerRadius: SPRadius.tile, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: SPRadius.tile).stroke(Color.spInk, lineWidth: selection == s.id ? 2 : 0))
                            .opacity(s.isAvailable ? 1 : 0.45)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                Text("Shop Post es independiente y no está afiliada a ningún supermercado. Los precios pueden variar según la tienda, la zona y el momento.")
                    .font(.spCaption).foregroundStyle(Color.spSecondary)
            }
            .padding(24)
        }
        .presentationDetents([.large])
    }
}
