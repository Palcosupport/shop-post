import SwiftUI

struct AlertsView: View {
    @Environment(CatalogService.self) private var catalog
    @Environment(Preferences.self) private var prefs
    @State private var creating = false
    @State private var editing: PriceAlert?
    @State private var showing: PriceAlert?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    ScreenTitle(title: "Alertas", subtitle: "Te avisamos cuando haya ofertas o bajadas")
                    CircleButton(systemName: "plus", filled: true, size: 56) { creating = true }
                }
                if prefs.alerts.isEmpty {
                    EmptyCard(title: "Sin alertas todavía",
                              message: "Por ejemplo: «café» con bajadas de más del 10 %, o las ofertas de un producto concreto.",
                              buttonTitle: "Crear alerta") { creating = true }
                }
                ForEach(prefs.alerts) { alert in
                    let matches = AlertEngine.shared.matches(for: alert, catalog: catalog)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 14) {
                            Image(systemName: alert.kind.icon).font(.system(size: 20))
                                .frame(width: 48, height: 48).background(Color.spSurface, in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(alert.title).font(.spHeadline).lineLimit(1)
                                Text(detail(alert)).font(.spCaption).foregroundStyle(Color.spSecondary).lineLimit(2)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(get: { alert.enabled }, set: { v in
                                if let i = prefs.alerts.firstIndex(where: { $0.id == alert.id }) { prefs.alerts[i].enabled = v }
                            }))
                            .labelsHidden()
                            .tint(Color.spInk)
                        }
                        HStack {
                            Button { showing = alert } label: {
                                Text(matches.isEmpty ? "Sin coincidencias ahora" : "Ver \(Count.items(matches.count, "coincidencia", "coincidencias"))")
                                    .font(.spSub.weight(.medium))
                                    .foregroundStyle(matches.isEmpty ? Color.spSecondary : Color.spInk)
                            }
                            .disabled(matches.isEmpty)
                            Spacer()
                            Menu {
                                Button { editing = alert } label: { Label("Editar", systemImage: "pencil") }
                                Button(role: .destructive) { prefs.alerts.removeAll { $0.id == alert.id } } label: {
                                    Label("Eliminar", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(Color.spSecondary).frame(width: 40, height: 30)
                            }
                        }
                    }
                    .spCard(padding: 18)
                    .opacity(alert.enabled ? 1 : 0.6)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, tabBarClearance)
        }
        .spScreen()
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $creating) { NavigationStack { AlertEditor(product: nil) }.spSheet() }
        .sheet(item: $editing) { x in NavigationStack { AlertEditor(product: nil, existing: x) }.spSheet() }
        .sheet(item: $showing) { alert in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(alert.title).font(.spTitle)
                        ProductCollection(products: AlertEngine.shared.matches(for: alert, catalog: catalog).prefix(200).map { catalog.byId[$0.id] ?? $0 },
                                          grid: true, showStore: true)
                    }
                    .padding(20)
                }
            }
            .spSheet()
        }
    }

    private func detail(_ a: PriceAlert) -> String {
        let stores = a.stores.isEmpty ? "Todos los súper" : a.stores.compactMap { catalog.store($0)?.name }.joined(separator: ", ")
        var parts = [stores]
        if a.minDrop > 0 { parts.append("mínimo \(a.minDrop) %") }
        return parts.joined(separator: " · ")
    }
}

struct AlertEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CatalogService.self) private var catalog
    @Environment(Preferences.self) private var prefs
    let product: Product?
    var existing: PriceAlert? = nil
    @State private var alert = PriceAlert()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(existing == nil ? "Nueva alerta" : "Editar alerta").font(.spTitle)
                if let product {
                    HStack(spacing: 12) {
                        Thumb(url: product.imageURL, size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(product.name).font(.spHeadline).lineLimit(2)
                            Text("Solo este producto").font(.spCaption).foregroundStyle(Color.spSecondary)
                        }
                    }
                    .spCard(padding: 14, radius: SPRadius.tile)
                } else if alert.productId == nil {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("¿Qué te interesa?").font(.spHeadline)
                        TextField("Palabras clave: café, aceite de oliva…", text: $alert.query)
                            .font(.spBody).padding(.horizontal, 20).frame(height: 56)
                            .background(Color.spChip, in: Capsule())
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Avisarme de").font(.spHeadline)
                    ChipBar(items: PriceAlert.Kind.allCases.filter { product == nil || $0 != .new }.map { ($0, $0.short, nil) },
                            selection: $alert.kind)
                }
                if alert.kind != .new {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Descuento mínimo").font(.spHeadline)
                            Spacer()
                            Text(alert.minDrop == 0 ? "Cualquiera" : "\(alert.minDrop) %").font(.spSub).foregroundStyle(Color.spSecondary)
                        }
                        Slider(value: Binding(get: { Double(alert.minDrop) }, set: { alert.minDrop = Int($0) }), in: 0...50, step: 5)
                            .tint(Color.spInk)
                    }
                    .spCard(padding: 18, radius: SPRadius.tile)
                }
                if product == nil {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Supermercados").font(.spHeadline)
                        FlowChips(stores: catalog.stores.filter(\.isAvailable), selected: $alert.stores)
                        Text(alert.stores.isEmpty ? "Ninguno marcado: todos." : "").font(.spCaption).foregroundStyle(Color.spSecondary)
                    }
                }
                PrimaryButton(title: "Guardar alerta", systemName: "bell") { save() }
                    .disabled(product == nil && alert.productId == nil && alert.query.trimmingCharacters(in: .whitespaces).isEmpty && alert.kind != .new)
            }
            .padding(24)
        }
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Image(systemName: "xmark") } } }
        .onAppear {
            if let existing { alert = existing }
            else if let product {
                alert.productId = product.id
                alert.productName = product.name
                alert.kind = .any
            }
        }
    }

    private func save() {
        var a = alert
        a.query = a.query.trimmingCharacters(in: .whitespaces)
        // Lo que ya coincide ahora no se notifica: solo lo nuevo a partir de hoy.
        a.seen = AlertEngine.shared.matches(for: a, catalog: catalog).map { $0.id + "@\($0.price)" }
        if let i = prefs.alerts.firstIndex(where: { $0.id == a.id }) { prefs.alerts[i] = a } else { prefs.alerts.insert(a, at: 0) }
        AlertEngine.shared.requestPermission()
        ShopModel.shared.show("Alerta guardada")
        dismiss()
    }
}

struct FlowChips: View {
    let stores: [StoreInfo]
    @Binding var selected: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(stores) { s in
                Chip(title: s.name, selected: selected.contains(s.id)) {
                    if let i = selected.firstIndex(of: s.id) { selected.remove(at: i) } else { selected.append(s.id) }
                }
            }
        }
    }
}

struct HistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ShopModel.self) private var shop
    @Environment(Preferences.self) private var prefs
    var closable = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScreenTitle(title: "Compras anteriores", subtitle: "Se guardan al terminar una compra en la cesta")
                if prefs.history.isEmpty {
                    EmptyCard(title: "Aún no hay compras",
                              message: "Cuando termines una compra (Cesta → ··· → Terminar compra) la verás aquí para repetirla.")
                }
                ForEach(prefs.history) { record in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.date.formatted(.dateTime.weekday(.wide).day().month(.wide))).font(.spHeadline)
                                Text("\(record.groupName) · \(Count.items(record.lines.count)) · \(Money.string(record.total))")
                                    .font(.spCaption).foregroundStyle(Color.spSecondary)
                            }
                            Spacer()
                        }
                        HStack(spacing: -10) {
                            ForEach(Array(record.lines.prefix(6).enumerated()), id: \.offset) { _, l in
                                Thumb(url: l.image.flatMap(URL.init(string:)), size: 44)
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.spCard, lineWidth: 3))
                            }
                        }
                        HStack(spacing: 10) {
                            PrimaryButton(title: "Repetir compra", systemName: "arrow.clockwise") {
                                shop.repeatPurchase(record)
                                if closable { dismiss() }
                            }
                            Button(role: .destructive) { prefs.history.removeAll { $0.id == record.id } } label: {
                                Image(systemName: "trash").font(.system(size: 18))
                                    .foregroundStyle(Color.spRed).frame(width: 56, height: 56)
                                    .background(Color.spRedSoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                    .spCard(padding: 18)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, tabBarClearance)
        }
        .spScreen()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if closable { ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Image(systemName: "xmark") } } }
        }
    }
}
