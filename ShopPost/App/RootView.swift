import SwiftUI

struct RootView: View {
    @Environment(ShopModel.self) private var shop
    @Environment(CatalogService.self) private var catalog
    @Environment(Preferences.self) private var prefs

    var body: some View {
        @Bindable var shop = shop
        TabView(selection: $shop.tab) {
            Tab(value: AppTab.home) { tabContent { HomeView() } }
            Tab(value: AppTab.catalog) { tabContent { CatalogView() } }
            Tab(value: AppTab.basket) { tabContent { BasketView() } }
            Tab(value: AppTab.pantry) { tabContent { PantryView() } }
        }
        .overlay(alignment: .bottom) {
            SPTabBar(selection: $shop.tab, onAdd: { shop.showAddSheet = true },
                     basketCount: basketPending)
                .padding(.bottom, 2)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
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

    private func tabContent<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        NavigationStack { content() }
            .toolbarVisibility(.hidden, for: .tabBar)
    }

    private var basketPending: Int {
        _ = shop.revision
        return shop.activeGroup?.itemList.filter { !$0.checked }.count ?? 0
    }
}
