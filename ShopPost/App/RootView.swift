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
            Tab("Inicio", systemImage: "house", value: AppTab.home) {
                NavigationStack { HomeView() }
            }
            Tab("Catálogo", systemImage: "books.vertical", value: AppTab.catalog) {
                NavigationStack { CatalogView() }
            }
            Tab("Añadir", systemImage: "plus.circle", value: AppTab.add) {
                Color.spBackground
            }
            Tab("Cesta", systemImage: "basket", value: AppTab.basket) {
                NavigationStack { BasketView() }
            }
            .badge(basketPending)
            Tab("Despensa", systemImage: "cabinet", value: AppTab.pantry) {
                NavigationStack { PantryView() }
            }
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

    private var basketPending: Int {
        _ = shop.revision
        return shop.activeGroup?.itemList.filter { !$0.checked }.count ?? 0
    }
}
