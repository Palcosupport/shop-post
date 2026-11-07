import CloudKit
import SwiftUI
import UIKit

// MARK: - Notas y sustituto

struct ItemNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ShopModel.self) private var shop
    @Environment(CatalogService.self) private var catalog
    @ObservedObject var item: SPItem
    @State private var note = ""
    @State private var substitute: Product?
    @State private var clearedSubstitute = false
    @State private var picking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Thumb(url: item.imageURL, size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notas del producto").font(.spTitle)
                        Text(item.title).font(.spSub).foregroundStyle(Color.spSecondary).lineLimit(1)
                    }
                }
                TextField("Ej.: si no queda, coge el de al lado", text: $note, axis: .vertical)
                    .lineLimit(3...6)
                    .font(.spBody)
                    .padding(18)
                    .background(Color.spCard, in: RoundedRectangle(cornerRadius: SPRadius.tile, style: .continuous))
                    .onChange(of: note) { _, v in if v.count > 280 { note = String(v.prefix(280)) } }
                Text("\(note.count)/280").font(.spCaption).foregroundStyle(Color.spTertiary).frame(maxWidth: .infinity, alignment: .trailing)

                SectionHeader(title: "Sustituto", subtitle: "Qué comprar si no queda")
                if let sub = substitute ?? (clearedSubstitute ? nil : catalog.product(item.substituteId)) {
                    HStack(spacing: 12) {
                        Thumb(url: sub.imageURL, size: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(sub.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                            Text("\(catalog.store(sub.store)?.name ?? sub.store) · \(Money.string(sub.price))")
                                .font(.spCaption).foregroundStyle(Color.spSecondary)
                        }
                        Spacer()
                        Button { substitute = nil; clearedSubstitute = true } label: {
                            Image(systemName: "xmark").frame(width: 36, height: 36).background(Color.spSurface, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .spCard(padding: 14, radius: SPRadius.tile)
                } else if !clearedSubstitute, let name = item.substituteName {
                    Text(name).spCard(padding: 16, radius: SPRadius.tile)
                }
                Button { picking = true } label: {
                    OptionRow(icon: "arrow.triangle.swap", title: "Elegir sustituto", subtitle: "Busca una alternativa en el catálogo", circled: true)
                }
                .buttonStyle(PressableStyle())

                PrimaryButton(title: "Guardar", systemName: "checkmark") {
                    item.note = note.isEmpty ? nil : note
                    if let substitute {
                        item.substituteId = substitute.id
                        item.substituteName = substitute.name
                        item.substitutePrice = substitute.price
                        item.substituteImage = substitute.image
                    } else if clearedSubstitute {
                        item.substituteId = nil; item.substituteName = nil; item.substitutePrice = 0; item.substituteImage = nil
                    }
                    shop.db.save()
                    dismiss()
                }
                .padding(.top, 6)
            }
            .padding(16)
        }
        .onAppear { note = item.note ?? "" }
        .sheet(isPresented: $picking) {
            NavigationStack {
                ProductPicker(initialQuery: Text2.tokens(item.title).prefix(2).joined(separator: " ")) { p in
                    substitute = p; clearedSubstitute = false
                }
            }
            .spSheet()
        }
    }
}

/// Buscador para elegir un producto (sustitutos, despensa…).
struct ProductPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CatalogService.self) private var catalog
    @Environment(Preferences.self) private var prefs
    var initialQuery = ""
    var title = "Elegir producto"
    let onPick: (Product) -> Void
    @State private var query = ""

    var body: some View {
        let results = query.count < 2 ? [] : catalog.search(query, stores: Set(prefs.visibleStores(in: catalog).map(\.id)), limit: 80)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SearchField(text: $query)
                ForEach(results) { p in
                    Button { onPick(p); dismiss() } label: {
                        HStack(spacing: 12) {
                            Thumb(url: p.imageURL, size: 56)
                            VStack(alignment: .leading, spacing: 3) {
                                StoreName(storeId: p.store)
                                Text(p.name).font(.subheadline.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                                Text(p.subtitle).font(.spCaption).foregroundStyle(Color.spSecondary)
                            }
                            Spacer()
                            Text(Money.string(p.price)).font(.spHeadline)
                        }
                        .foregroundStyle(Color.spInk)
                        .padding(12)
                        .background(Color.spCard, in: RoundedRectangle(cornerRadius: SPRadius.tile, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                }
                if query.count >= 2 && results.isEmpty {
                    Text("Sin resultados").font(.spSub).foregroundStyle(Color.spSecondary).frame(maxWidth: .infinity).padding()
                }
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Image(systemName: "xmark") } } }
        .onAppear { if query.isEmpty { query = initialQuery } }
    }
}

// MARK: - Comparar la cesta

struct CompareSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CatalogService.self) private var catalog
    @Environment(Preferences.self) private var prefs
    let items: [SPItem]
    @State private var rows: [Row] = []
    @State private var expanded: String?

    struct Row: Identifiable {
        let id: String
        let total: Double
        let found: Int
        let lines: [(String, Product?)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Tu cesta en cada supermercado").font(.spTitle)
                Text("Buscamos el producto equivalente más parecido de cada artículo y lo calculamos para la misma cantidad (por €/kg o €/L). Los totales solo incluyen lo que se ha encontrado.")
                    .font(.spSub).foregroundStyle(Color.spSecondary)
                if rows.isEmpty { ProgressView().frame(maxWidth: .infinity).padding(40) }
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    VStack(alignment: .leading, spacing: 12) {
                        Button { withAnimation(.snappy) { expanded = expanded == row.id ? nil : row.id } } label: {
                            HStack(spacing: 14) {
                                StoreBadge(storeId: row.id, size: 40)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(catalog.store(row.id)?.name ?? row.id).font(.spHeadline)
                                        if index == 0 && row.found > 0 { Badge(text: "Más barata", color: .spGreen, soft: .spGreenSoft) }
                                    }
                                    Text("\(row.found) de \(items.count) encontrados").font(.spCaption).foregroundStyle(Color.spSecondary)
                                }
                                Spacer()
                                Text(Money.string(row.total)).font(.title3.weight(.bold)).monospacedDigit()
                            }
                            .foregroundStyle(Color.spInk)
                        }
                        .buttonStyle(.plain)
                        if expanded == row.id {
                            ForEach(Array(row.lines.enumerated()), id: \.offset) { _, line in
                                HStack {
                                    Text(line.1?.name ?? line.0).font(.spCaption).lineLimit(1)
                                        .foregroundStyle(line.1 == nil ? Color.spTertiary : Color.spInk)
                                    Spacer()
                                    Text(line.1.map { Money.string($0.price) } ?? "—").font(.spCaption.weight(.medium))
                                }
                            }
                        }
                    }
                    .spCard(padding: 18)
                }
            }
            .padding(16)
        }
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Image(systemName: "xmark") } } }
        .task { await compute() }
    }

    private struct Wanted: Sendable {
        let title, productId, store, brand, cat, unit: String?
        let price, unitPrice: Double
        let quantity: Int
    }

    private func compute() async {
        let stores = prefs.visibleStores(in: catalog).map(\.id)
        let catalogLists = catalog.productsByStore
        let byId = catalog.byId
        let wanted = items.map { Wanted(title: $0.title, productId: $0.productId, store: $0.store, brand: $0.brand,
                                        cat: $0.cat, unit: $0.unit, price: $0.price, unitPrice: $0.unitPrice,
                                        quantity: Int(max($0.quantity, 1))) }
        rows = await Task.detached(priority: .userInitiated) {
            var out: [Row] = []
            for sid in stores {
                guard let list = catalogLists[sid] else { continue }
                var total = 0.0, found = 0
                var lines: [(String, Product?)] = []
                for w in wanted {
                    let match: Product?
                    if w.store == sid, let pid = w.productId, let p = byId[pid] {
                        match = p
                    } else {
                        match = Matching.bestMatch(name: w.title ?? "", brand: w.brand, cat: w.cat, unit: w.unit, in: list)
                    }
                    if let match {
                        // Misma cantidad que el original: por €/kg o €/L cuando se puede (1 L frente a 5 L).
                        var cost = match.price
                        if w.store != sid, w.unitPrice > 0, w.price > 0, let mu = match.unitPrice, mu > 0, match.unit == w.unit {
                            cost = mu * (w.price / w.unitPrice)
                        }
                        total += cost * Double(w.quantity)
                        found += 1
                    }
                    lines.append((w.title ?? "", match))
                }
                out.append(Row(id: sid, total: total, found: found, lines: lines))
            }
            // Primero los que encuentran más artículos y, a igualdad, los más baratos.
            return out.sorted { ($0.found, -$0.total) > ($1.found, -$1.total) }
        }.value
    }
}

// MARK: - Grupos

struct GroupEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ShopModel.self) private var shop
    let group: SPGroup?
    @State private var name = ""
    @State private var emoji = "🛒"

    static let emojis = ["🛒", "🏠", "🧺", "🛍️", "🍎", "🥦", "🍝", "🧀", "🥖", "🍷", "🎉", "🏖️", "🏡", "👨‍👩‍👧", "💑", "🎓", "🏢", "⛺️"]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(group == nil ? "Nuevo grupo" : "Editar grupo").font(.spTitle)
            Text("Cada grupo tiene su propia cesta y despensa. Puedes compartirlo con tu pareja, familia o piso.")
                .font(.spSub).foregroundStyle(Color.spSecondary)
            TextField("Nombre (Casa, Piso, Pueblo…)", text: $name)
                .font(.spBody)
                .padding(.horizontal, 14).frame(minHeight: 44)
                .background(Color.spChip, in: Capsule())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.emojis, id: \.self) { e in
                        Button { emoji = e } label: {
                            Text(e).font(.title).frame(width: 52, height: 52)
                                .background(emoji == e ? Color.spCardStrong : Color.spCard, in: Circle())
                                .overlay(Circle().stroke(Color.spInk, lineWidth: emoji == e ? 2 : 0))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer()
            PrimaryButton(title: group == nil ? "Crear grupo" : "Guardar") {
                let n = name.trimmingCharacters(in: .whitespaces)
                if let group {
                    group.name = n.isEmpty ? group.title : n
                    group.emoji = emoji
                    shop.db.save()
                } else {
                    shop.createGroup(name: n.isEmpty ? "Mi grupo" : n, emoji: emoji)
                }
                dismiss()
            }
        }
        .padding(16)
        .onAppear { name = group?.name ?? ""; emoji = group?.icon ?? "🛒" }
    }
}

struct GroupDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ShopModel.self) private var shop
    @ObservedObject var group: SPGroup
    @State private var editing = false
    @State private var sharing = false
    @State private var confirmDelete = false

    var body: some View {
        let db = Persistence.shared
        let members = db.participants(of: group)
        let isOwner = db.isOwner(group)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 16) {
                    Text(group.icon).font(.largeTitle).frame(width: 84, height: 84).background(Color.spCard, in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.title).font(.spLargeTitle)
                        Text(db.isShared(group) ? "Grupo compartido" : "Solo tú").font(.spSub).foregroundStyle(Color.spSecondary)
                    }
                }
                HStack(spacing: 10) {
                    StatTile(icon: "basket", value: "\(group.itemList.count)", label: "En la cesta")
                    StatTile(icon: "cabinet", value: "\(group.pantryList.count)", label: "En casa")
                    StatTile(icon: "person.2", value: "\(max(1, members.count))", label: "Miembros")
                }
                SectionHeader(title: "Miembros")
                if members.isEmpty {
                    Text("Invita a otras personas para que vean y editen la misma cesta en tiempo real con su iPhone.")
                        .font(.spSub).foregroundStyle(Color.spSecondary)
                }
                ForEach(members, id: \.self) { m in
                    HStack(spacing: 14) {
                        Image(systemName: "person.crop.circle.fill").font(.largeTitle).foregroundStyle(Color.spSecondary)
                        VStack(alignment: .leading) {
                            Text(m.userIdentity.nameComponents.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) } ?? "Invitado")
                                .font(.spHeadline)
                            Text(m.role == .owner ? "Administrador" : (m.permission == .readWrite ? "Puede editar" : "Solo lectura"))
                                .font(.spCaption).foregroundStyle(Color.spSecondary)
                        }
                        Spacer()
                    }
                    .spCard(padding: 14, radius: SPRadius.tile)
                }
                Button { sharing = true } label: {
                    OptionRow(icon: "person.badge.plus", title: "Invitar personas", subtitle: "Comparte un enlace por WhatsApp, Mensajes…", circled: true)
                }
                .buttonStyle(PressableStyle())
                if isOwner {
                    Button { editing = true } label: {
                        OptionRow(icon: "pencil", title: "Nombre e icono", subtitle: group.title, circled: true)
                    }
                    .buttonStyle(PressableStyle())
                }
                Button { shop.setActive(group); dismiss() } label: {
                    OptionRow(icon: "checkmark.circle", title: "Usar como cesta activa", circled: true)
                }
                .buttonStyle(PressableStyle())
                Button(role: .destructive) { confirmDelete = true } label: {
                    Text(isOwner ? "Eliminar grupo" : "Salir del grupo")
                        .font(.body.weight(.medium)).foregroundStyle(Color.spRed)
                        .frame(maxWidth: .infinity).frame(minHeight: 44)
                        .background(Color.spRedSoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .buttonStyle(PressableStyle())
                .disabled(shop.groups().count <= 1)
            }
            .padding(16)
        }
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Image(systemName: "xmark") } } }
        .sheet(isPresented: $editing) { NavigationStack { GroupEditor(group: group) }.spSheet().presentationDetents([.medium]) }
        .sheet(isPresented: $sharing) { CloudShareView(group: group).ignoresSafeArea() }
        .confirmationDialog(isOwner ? "Se borrarán la cesta y la despensa de este grupo para todos sus miembros." : "Dejarás de ver este grupo.",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(isOwner ? "Eliminar grupo" : "Salir del grupo", role: .destructive) {
                let wasActive = shop.activeGroup?.objectID == group.objectID
                Persistence.shared.purge(group)
                if wasActive, let first = shop.groups().first(where: { $0.objectID != group.objectID }) { shop.setActive(first) }
                dismiss()
            }
        }
    }
}

// MARK: - Compartir con iCloud

struct CloudShareView: UIViewControllerRepresentable {
    let group: SPGroup

    func makeUIViewController(context: Context) -> UIViewController {
        let db = Persistence.shared
        guard db.cloudEnabled else {
            let alert = UIAlertController(title: "iCloud no disponible",
                                          message: "Inicia sesión en iCloud en Ajustes para compartir grupos con otras personas.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Aceptar", style: .default))
            let host = UIViewController()
            DispatchQueue.main.async { host.present(alert, animated: true) }
            return host
        }
        let controller: UICloudSharingController
        if let share = db.existingShare(for: group) {
            controller = UICloudSharingController(share: share, container: db.ckContainer)
        } else {
            controller = UICloudSharingController { _, completion in
                Task {
                    do {
                        let share = try await db.share(group)
                        completion(share, db.ckContainer, nil)
                    } catch {
                        completion(nil, nil, error)
                    }
                }
            }
        }
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.delegate = context.coordinator
        controller.modalPresentationStyle = .formSheet
        return controller
    }

    func updateUIViewController(_ vc: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(group: group) }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let group: SPGroup
        init(group: SPGroup) { self.group = group }

        func itemTitle(for csc: UICloudSharingController) -> String? { "Grupo \(group.title) en Shop Post" }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            print("Error al compartir:", error)
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            Task { @MainActor in ShopModel.shared.revision &+= 1 }
        }
    }
}
