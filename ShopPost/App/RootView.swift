import SwiftUI

struct RootView: View {
    @Environment(ShopModel.self) private var shop
    @Environment(CatalogService.self) private var catalog
    @Environment(Preferences.self) private var prefs

    var body: some View {
        @Bindable var shop = shop
        // La pestaña «Añadir» no se queda seleccionada: abre la hoja y vuelve a la pestaña anterior.
        let selection = Binding<AppTab>(
            get: { shop.tab },
            set: { newTab in
                if newTab == .add { shop.showAddSheet = true } else { shop.tab = newTab }
            })
        TabView(selection: selection) {
            Tab(value: AppTab.home) {
                NavigationStack { HomeView() }
            } label: { tabLabel("Inicio", "square.on.square") }
            Tab(value: AppTab.pantry) {
                NavigationStack { PantryView() }
            } label: { tabLabel("Despensa", "server.rack") }
            Tab(value: AppTab.add) {
                Color.spBackground
            } label: { tabLabel("Añadir", "plus.circle") }
            Tab(value: AppTab.catalog) {
                NavigationStack { CatalogView() }
            } label: { tabLabel("Catálogo", "square.text.square") }
            Tab(value: AppTab.basket) {
                NavigationStack { BasketView() }
            } label: { tabLabel("Cesta", "bag") }
            .badge(basketPending)
        }
        .overlay(alignment: .top) {
            if let toast = shop.toast {
                Toast(text: toast)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: shop.toast)
        .sheet(isPresented: $shop.showAddSheet) { AddSheet().spSheet() }
        .sheet(item: $shop.presentedProduct) { p in
            NavigationStack { ProductDetailView(product: p) }.spSheet()
        }
        .fullScreenCover(isPresented: Binding(get: { !prefs.onboarded }, set: { if !$0 { prefs.onboarded = true } })) {
            OnboardingView()
        }
        .task {
            shop.ensureDefaultGroup()
            await catalog.bootstrap()
        }
    }

    /// Icono de línea (sin relleno): la barra de pestañas de iOS los rellena por defecto.
    private func tabLabel(_ title: String, _ symbol: String) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol).environment(\.symbolVariants, .none)
        }
    }

    private var basketPending: Int {
        _ = shop.revision
        return shop.activeGroup?.itemList.filter { !$0.checked }.count ?? 0
    }
}
