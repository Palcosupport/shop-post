import SwiftUI
import UserNotifications

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ShopModel.self) private var shop
    @Environment(CatalogService.self) private var catalog
    @Environment(Preferences.self) private var prefs
    @State private var showStores = false
    @State private var showSettings = false
    @State private var groupDetail: SPGroup?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Group {
                        if prefs.initials.isEmpty {
                            Image(systemName: "person.fill").font(.title2).foregroundStyle(Color.spSecondary)
                        } else {
                            Text(prefs.initials).font(.title3.weight(.semibold))
                        }
                    }
                    .frame(width: 60, height: 60)
                    .background(Color.spCard, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(prefs.userName.isEmpty ? "Tu perfil" : prefs.userName).font(.title2.weight(.bold)).lineLimit(1)
                        Text("Tu compra, sin olvidos.").font(.subheadline).foregroundStyle(Color.spSecondary)
                    }
                    Spacer()
                }
                .padding(.bottom, 4)

                Button { showStores = true } label: {
                    OptionRow(icon: "storefront", title: "Tus supermercados",
                              subtitle: prefs.favoriteStores.isEmpty ? "Todos · elige tus favoritos" : prefs.visibleStores(in: catalog).map(\.name).joined(separator: ", "),
                              tint: .spGold)
                }

                SectionHeader(title: "Tu compra", subtitle: "Lo que Shop Post guarda para ti").padding(.top, 6)
                NavigationLink(value: HomeRoute.alerts) {
                    OptionRow(icon: "bell", title: "Alertas de ahorro", subtitle: "\(prefs.alerts.filter(\.enabled).count) activas")
                }
                NavigationLink(value: HomeRoute.feed(.favorites)) {
                    OptionRow(icon: "star", title: "Favoritos", subtitle: Count.items(prefs.favorites.count, "producto", "productos"))
                }
                NavigationLink(value: HomeRoute.history) {
                    OptionRow(icon: "clock.arrow.circlepath", title: "Compras anteriores", subtitle: "Repite una lista con un toque")
                }

                SectionHeader(title: "Tus grupos", subtitle: "Cesta y despensa compartidas").padding(.top, 6)
                ForEach(shop.groups()) { g in
                    Button { groupDetail = g } label: {
                        OptionRow(icon: Persistence.shared.isShared(g) ? "person.2" : "house", title: "\(g.icon)  \(g.title)",
                                  subtitle: "\(Count.items(g.itemList.count)) en la cesta · \(Count.items(g.pantryList.count, "producto", "productos")) en casa")
                    }
                }

                SectionHeader(title: "Más").padding(.top, 6)
                Button { showSettings = true } label: {
                    OptionRow(icon: "gearshape", title: "Ajustes", subtitle: "Nombre, personalización, notificaciones y datos")
                }
                NavigationLink(value: "about") {
                    OptionRow(icon: "info.circle", title: "Acerca de Shop Post", subtitle: "Fuentes de datos y aviso legal")
                }
            }
            .buttonStyle(PressableStyle())
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .spScreen()
        .navigationDestination(for: HomeRoute.self) { route in
            switch route {
            case .feed(let f): ProductFeedView(feed: f)
            case .alerts: AlertsView()
            case .history: HistoryView()
            case .profile: EmptyView()
            }
        }
        .navigationDestination(for: String.self) { _ in AboutView() }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Image(systemName: "xmark") } }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Ajustes")
            }
        }
        .sheet(isPresented: $showStores) { NavigationStack { FavoriteStoresView() }.spSheet() }
        .sheet(isPresented: $showSettings) { NavigationStack { SettingsView() }.spSheet() }
        .sheet(item: $groupDetail) { x in NavigationStack { GroupDetailView(group: x) }.spSheet() }
    }
}

struct FavoriteStoresView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CatalogService.self) private var catalog
    @Environment(Preferences.self) private var prefs

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Tus supermercados").font(.spTitle)
                Text("Elige dónde sueles comprar. Solo verás y compararás precios de estos. Sin ninguno marcado se usan todos.")
                    .font(.spSub).foregroundStyle(Color.spSecondary)
                ForEach(catalog.stores) { s in
                    let on = prefs.favoriteStores.contains(s.id)
                    Button {
                        if on { prefs.favoriteStores.removeAll { $0 == s.id } } else { prefs.favoriteStores.append(s.id) }
                        Haptics.tap()
                    } label: {
                        HStack(spacing: 14) {
                            StoreBadge(storeId: s.id, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.name).font(.spHeadline)
                                Text(s.isAvailable ? "\(Count.string(s.count ?? 0)) productos" : "Sin datos ahora mismo")
                                    .font(.spCaption).foregroundStyle(Color.spSecondary)
                            }
                            Spacer()
                            if prefs.defaultStore == s.id {
                                Badge(text: "Por defecto", color: .spInk, soft: .spCardStrong)
                            }
                            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                .font(.title2.weight(.light))
                                .foregroundStyle(on ? Color.spAccent : Color.spTertiary)
                        }
                        .foregroundStyle(Color.spInk)
                        .spCard(padding: 16, radius: SPRadius.tile)
                        .opacity(s.isAvailable ? 1 : 0.5)
                    }
                    .buttonStyle(PressableStyle())
                    .contextMenu {
                        Button(prefs.defaultStore == s.id ? "Quitar como predeterminado" : "Abrir el catálogo en este súper") {
                            prefs.defaultStore = prefs.defaultStore == s.id ? nil : s.id
                        }
                    }
                }
                Text("Mantén pulsado un supermercado para que el catálogo se abra siempre en él.")
                    .font(.spCaption).foregroundStyle(Color.spSecondary)
            }
            .padding(16)
        }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Hecho") { dismiss() } } }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CatalogService.self) private var catalog
    @Environment(Preferences.self) private var prefs
    @State private var dataURL = ""
    @State private var notifStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        @Bindable var prefs = prefs
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Ajustes").font(.spTitle)
                field("Tu nombre", text: $prefs.userName, hint: "Se muestra a tu grupo al recoger o asignar productos.")
                AccentPicker()
                VStack(alignment: .leading, spacing: 10) {
                    Text("Notificaciones").font(.spHeadline)
                    Text(notifStatus == .authorized ? "Activadas: te avisaremos de tus alertas de ahorro." : "Actívalas para recibir tus alertas de ahorro.")
                        .font(.spSub).foregroundStyle(Color.spSecondary)
                    if notifStatus != .authorized {
                        PrimaryButton(title: notifStatus == .denied ? "Abrir Ajustes del iPhone" : "Activar notificaciones", style: .soft) {
                            if notifStatus == .denied, let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            } else {
                                AlertEngine.shared.requestPermission()
                                Task { try? await Task.sleep(for: .seconds(1)); await loadStatus() }
                            }
                        }
                    }
                }
                .spCard(padding: 18, radius: SPRadius.tile)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Datos de precios").font(.spHeadline)
                    Text("Última actualización: \(catalog.lastUpdate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "nunca") · \(Count.string(catalog.totalCount)) productos")
                        .font(.spSub).foregroundStyle(Color.spSecondary)
                    TextField("URL del servidor", text: $dataURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .font(.system(size: 14, design: .monospaced))
                        .padding(.horizontal, 16).frame(height: 48)
                        .background(Color.spChip, in: Capsule())
                    HStack(spacing: 10) {
                        PrimaryButton(title: "Actualizar ahora", style: .soft) {
                            catalog.dataURLString = dataURL
                            Task { await catalog.refresh(force: true) }
                        }
                        PrimaryButton(title: "Por defecto", style: .soft) {
                            dataURL = CatalogService.defaultDataURL
                        }
                    }
                    if case .failed(let msg) = catalog.state { Text(msg).font(.spCaption).foregroundStyle(Color.spRed) }
                }
                .spCard(padding: 18, radius: SPRadius.tile)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Privacidad").font(.spHeadline)
                    Text("Tus listas, grupos y despensa se guardan en tu iPhone y en tu iCloud. Solo las personas que invitas a un grupo pueden verlo. Los precios se descargan de un servidor público sin enviar ningún dato tuyo.")
                        .font(.spSub).foregroundStyle(Color.spSecondary)
                }
                .spCard(padding: 18, radius: SPRadius.tile)
            }
            .padding(16)
        }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Hecho") { catalog.dataURLString = dataURL; dismiss() } } }
        .onAppear { dataURL = catalog.dataURLString }
        .task { await loadStatus() }
    }

    private func loadStatus() async {
        notifStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func field(_ title: String, text: Binding<String>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.spHeadline)
            TextField(title, text: text)
                .font(.spBody).padding(.horizontal, 14).frame(minHeight: 44)
                .background(Color.spChip, in: Capsule())
            Text(hint).font(.spCaption).foregroundStyle(Color.spSecondary)
        }
        .spCard(padding: 18, radius: SPRadius.tile)
    }
}

/// Ajustes › Personalización: color de acento de la app.
struct AccentPicker: View {
    @Environment(Preferences.self) private var prefs

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Personalización").font(.spHeadline)
            Text("Color de acento para botones, selecciones y la pestaña activa.")
                .font(.spSub).foregroundStyle(Color.spSecondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 14) {
                ForEach(AccentChoice.allCases) { choice in
                    let on = prefs.accent == choice
                    Button {
                        withAnimation(.snappy) { prefs.accent = choice }
                        Haptics.tap()
                    } label: {
                        VStack(spacing: 6) {
                            Circle()
                                .fill(choice.color)
                                .frame(width: 40, height: 40)
                                .overlay {
                                    if on {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 15, weight: .bold))
                                            .foregroundStyle(choice.onColor)
                                    }
                                }
                                .padding(3)
                                .overlay(Circle().strokeBorder(on ? choice.color : .clear, lineWidth: 2))
                            Text(choice.name)
                                .font(.caption.weight(on ? .semibold : .regular))
                                .foregroundStyle(on ? Color.spInk : Color.spSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel(choice.name)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
        .spCard(padding: 18, radius: SPRadius.tile)
    }
}

struct AboutView: View {
    @Environment(CatalogService.self) private var catalog

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Haz la lista de la compra con los productos reales de tu supermercado, compártela con tu casa, compara precios y entérate de las ofertas y bajadas.")
                    .font(.spBody)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Fuentes").font(.spHeadline)
                    Text("Los catálogos y precios se leen cada día de las tiendas online públicas de los supermercados. La información nutricional procede de Open Food Facts (licencia ODbL).")
                        .font(.spSub).foregroundStyle(Color.spSecondary)
                    ForEach(catalog.stores) { s in
                        HStack {
                            StoreName(storeId: s.id)
                            Spacer()
                            Text(s.status == "ok" ? "Al día" : "Sin datos").font(.spCaption)
                                .foregroundStyle(s.status == "ok" ? Color.spGreen : Color.spRed)
                        }
                    }
                }
                .spCard(padding: 18, radius: SPRadius.tile)
                Text("Shop Post es una app independiente y no está afiliada, patrocinada ni respaldada por ninguno de los supermercados mostrados. Las marcas pertenecen a sus propietarios. Los precios son orientativos y pueden variar según la tienda, la zona o el momento.")
                    .font(.spCaption).foregroundStyle(Color.spSecondary)
            }
            .padding(16)
        }
        .spScreen()
        .navigationTitle("Shop Post")
        .navigationSubtitle("Versión \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
    }
}

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CatalogService.self) private var catalog
    @Environment(Preferences.self) private var prefs
    @State private var step = 0
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer()
            if step == 0 {
                Image(systemName: "basket").font(.largeTitle.weight(.light))
                    .frame(width: 120, height: 120)
                    .background(Color.spCard, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
                BrandHeader()
                Text("La lista de la compra, con los productos de tu supermercado.").font(.spLargeTitle)
                Text("Compara precios, descubre ofertas y comparte la cesta con tu casa.").font(.spBody).foregroundStyle(Color.spSecondary)
                Spacer()
                PrimaryButton(title: "Empezar") { withAnimation { step = 1 } }
            } else if step == 1 {
                Text("¿Cómo te llamas?").font(.spLargeTitle)
                Text("Tu grupo verá tu nombre cuando recojas o añadas productos.").font(.spBody).foregroundStyle(Color.spSecondary)
                TextField("Tu nombre", text: $name)
                    .font(.title3).padding(.horizontal, 22).frame(minHeight: 48)
                    .background(Color.spChip, in: Capsule())
                    .submitLabel(.next)
                    .onSubmit { next() }
                Spacer()
                PrimaryButton(title: "Continuar") { next() }
            } else {
                Text("Te avisamos cuando baje").font(.spLargeTitle)
                Text("Crea alertas para tus productos y te enviaremos una notificación cuando haya ofertas o bajadas de precio.")
                    .font(.spBody).foregroundStyle(Color.spSecondary)
                Spacer()
                PrimaryButton(title: "Activar notificaciones", systemName: "bell") {
                    AlertEngine.shared.requestPermission()
                    prefs.onboarded = true
                    dismiss()
                }
                Button("Ahora no") { prefs.onboarded = true; dismiss() }
                    .font(.spBody).foregroundStyle(Color.spSecondary).frame(maxWidth: .infinity)
            }
        }
        .padding(28)
        .spScreen()
    }

    private func next() {
        prefs.userName = name.trimmingCharacters(in: .whitespaces)
        withAnimation { step = 2 }
    }
}
