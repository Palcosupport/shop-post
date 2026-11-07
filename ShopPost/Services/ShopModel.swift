import CoreData
import Observation
import SwiftUI

/// Estado de la app y acciones sobre grupos, cesta y despensa.
@Observable
@MainActor
final class ShopModel {
    static let shared = ShopModel()

    let db = Persistence.shared
    let prefs = Preferences.shared
    var tab: AppTab = .home
    var showAddSheet = false
    var catalogFocusSearch = false
    var presentedProduct: Product?
    var toast: String?
    /// Se incrementa al cambiar datos de Core Data para refrescar vistas calculadas.
    var revision = 0

    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(forName: .NSManagedObjectContextObjectsDidChange,
                                                          object: db.viewContext, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.revision &+= 1 }
        }
    }

    // MARK: Grupos

    func groups() -> [SPGroup] {
        let req = NSFetchRequest<SPGroup>(entityName: "SPGroup")
        req.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return (try? db.viewContext.fetch(req)) ?? []
    }

    var activeGroup: SPGroup? {
        _ = revision
        let all = groups()
        if let id = prefs.activeGroupID, let g = all.first(where: { $0.id?.uuidString == id }) { return g }
        return all.first
    }

    /// Garantiza que existe al menos un grupo ("Casa").
    func ensureDefaultGroup() {
        if groups().isEmpty {
            let g = createGroup(name: "Casa", emoji: "🏠")
            setupDefaultShelves(g)
            db.save()
        }
    }

    @discardableResult
    func createGroup(name: String, emoji: String) -> SPGroup {
        let g = db.insert(SPGroup.self, in: nil)
        g.id = UUID()
        g.name = name
        g.emoji = emoji
        g.createdAt = Date()
        setupDefaultShelves(g)
        db.save()
        prefs.activeGroupID = g.id?.uuidString
        return g
    }

    func setupDefaultShelves(_ g: SPGroup) {
        guard g.shelfList.isEmpty else { return }
        let defaults: [(String, String)] = [("Balda de arriba", "despensa"), ("Balda del medio", "despensa"),
                                            ("Balda de abajo", "despensa"), ("Puerta", "nevera"),
                                            ("Estante", "nevera"), ("Cajón", "congelador")]
        for (i, (name, place)) in defaults.enumerated() {
            let s = db.insert(SPShelf.self, in: g)
            s.id = UUID(); s.name = name; s.place = place; s.order = Int64(i); s.group = g
        }
    }

    func setActive(_ g: SPGroup) {
        prefs.activeGroupID = g.id?.uuidString
        revision &+= 1
    }

    // MARK: Cesta

    func basketItem(for productId: String, in group: SPGroup? = nil) -> SPItem? {
        (group ?? activeGroup)?.itemList.first { $0.productId == productId && !$0.checked }
    }

    func quantity(of productId: String) -> Int {
        _ = revision
        return Int(basketItem(for: productId)?.quantity ?? 0)
    }

    func setQuantity(_ product: Product, _ qty: Int) {
        guard let g = activeGroup else { return }
        if let item = basketItem(for: product.id, in: g) {
            if qty <= 0 { db.viewContext.delete(item) } else { item.quantity = Int64(qty) }
        } else if qty > 0 {
            add(product, quantity: qty, to: g, toastMessage: false)
        }
        db.save()
        Haptics.tap()
    }

    func add(_ product: Product, quantity: Int = 1, to group: SPGroup? = nil, toastMessage: Bool = true) {
        guard let g = group ?? activeGroup else { return }
        if let existing = basketItem(for: product.id, in: g) {
            existing.quantity += Int64(quantity)
        } else {
            let item = db.insert(SPItem.self, in: g)
            fill(item, with: product)
            item.quantity = Int64(quantity)
            item.group = g
        }
        db.save()
        if toastMessage { show("Añadido a \(g.title)") }
    }

    func fill(_ item: SPItem, with p: Product) {
        item.id = item.id ?? UUID()
        item.productId = p.id
        item.store = p.store
        item.name = p.name
        item.brand = p.brand
        item.image = p.image
        item.price = p.price
        item.size = p.size
        item.unit = p.unit
        item.unitPrice = p.unitPrice ?? 0
        item.cat = p.cat
        item.createdAt = item.createdAt ?? Date()
        item.addedBy = prefs.userName.isEmpty ? nil : prefs.userName
    }

    func addManual(name: String, quantity: Int, store: String?, price: Double, image: String? = nil, to group: SPGroup? = nil) {
        guard let g = group ?? activeGroup, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let item = db.insert(SPItem.self, in: g)
        item.id = UUID()
        item.name = name.trimmingCharacters(in: .whitespaces)
        item.quantity = Int64(max(quantity, 1))
        item.store = store
        item.price = price
        item.image = image
        item.cat = Text2.normalize(name).isEmpty ? "otros" : guessCategory(name)
        item.createdAt = Date()
        item.addedBy = prefs.userName.isEmpty ? nil : prefs.userName
        item.group = g
        db.save()
        show("Añadido a \(g.title)")
    }

    func guessCategory(_ name: String) -> String {
        let best = CatalogService.shared.search(name, limit: 20)
        let counts = Dictionary(grouping: best, by: \.cat).mapValues(\.count)
        return counts.max { $0.value < $1.value }?.key ?? "otros"
    }

    func toggleChecked(_ item: SPItem) {
        item.checked.toggle()
        item.checkedBy = item.checked ? (prefs.userName.isEmpty ? nil : prefs.userName) : nil
        db.save()
        Haptics.tap()
    }

    func delete(_ item: SPItem) {
        db.viewContext.delete(item)
        db.save()
    }

    /// Guarda en el historial lo recogido y lo quita de la cesta.
    func finishShopping(in g: SPGroup) {
        let done = g.itemList.filter(\.checked)
        guard !done.isEmpty else { return }
        let lines = done.map { PurchaseRecord.Line(productId: $0.productId, name: $0.title, store: $0.store,
                                                   image: $0.image, price: $0.price, quantity: Int($0.quantity), cat: $0.cat) }
        prefs.history.insert(PurchaseRecord(groupName: g.title, lines: lines), at: 0)
        prefs.history = Array(prefs.history.prefix(60))
        // Lo comprado repone la despensa.
        for item in done { restockPantry(from: item, in: g) }
        done.forEach(db.viewContext.delete)
        db.save()
        show("Compra guardada en el historial")
    }

    func clearAll(in g: SPGroup) {
        g.itemList.forEach(db.viewContext.delete)
        db.save()
    }

    func repeatPurchase(_ record: PurchaseRecord) {
        guard let g = activeGroup else { return }
        let catalog = CatalogService.shared
        for line in record.lines {
            if let p = catalog.product(line.productId) {
                add(p, quantity: line.quantity, to: g, toastMessage: false)
            } else {
                let item = db.insert(SPItem.self, in: g)
                item.id = UUID(); item.name = line.name; item.store = line.store; item.image = line.image
                item.price = line.price; item.quantity = Int64(line.quantity); item.cat = line.cat ?? "otros"
                item.createdAt = Date(); item.group = g
            }
        }
        db.save()
        show("\(Count.items(record.lines.count)) añadidos a \(g.title)")
    }

    // MARK: Despensa

    func pantryItems(in g: SPGroup?, place: String) -> [SPPantryItem] {
        _ = revision
        return (g?.pantryList ?? []).filter { ($0.place ?? "despensa") == place }
    }

    func missingPantry(in g: SPGroup?) -> [SPPantryItem] {
        _ = revision
        return (g?.pantryList ?? []).filter(\.isMissing)
    }

    func addToPantry(name: String, product: Product?, quantity: Int, place: String, shelf: SPShelf?, expiry: Date? = nil) {
        guard let g = activeGroup else { return }
        let p = db.insert(SPPantryItem.self, in: g)
        p.id = UUID()
        p.name = product?.name ?? name
        p.image = product?.image
        p.productId = product?.id
        p.store = product?.store
        p.price = product?.price ?? 0
        p.cat = product?.cat ?? guessCategory(name)
        p.quantity = Int64(quantity)
        p.minQuantity = 1
        p.place = place
        p.shelf = shelf ?? g.shelfList.first { $0.place == place }
        p.expiry = expiry
        p.createdAt = Date()
        p.group = g
        db.save()
        show("Guardado en la \(PantryPlace(rawValue: place)?.title.lowercased() ?? "despensa")")
    }

    func restockPantry(from item: SPItem, in g: SPGroup) {
        let match = g.pantryList.first { ($0.productId != nil && $0.productId == item.productId) ||
            Text2.normalize($0.name ?? "") == Text2.normalize(item.title) }
        if let match { match.quantity += item.quantity }
    }

    func moveMissingToBasket(_ items: [SPPantryItem]) {
        guard let g = activeGroup else { return }
        var added = 0
        for p in items {
            if let pid = p.productId, basketItem(for: pid, in: g) != nil { continue }
            if let product = CatalogService.shared.product(p.productId) {
                add(product, quantity: 1, to: g, toastMessage: false)
            } else {
                let item = db.insert(SPItem.self, in: g)
                item.id = UUID(); item.name = p.name; item.image = p.image; item.price = p.price
                item.store = p.store; item.cat = p.cat; item.quantity = 1; item.createdAt = Date(); item.group = g
            }
            added += 1
        }
        db.save()
        show(added == 0 ? "Ya estaba todo en la cesta" : "\(Count.items(added)) añadidos a la cesta")
    }

    func addShelf(name: String, place: String) {
        guard let g = activeGroup else { return }
        let s = db.insert(SPShelf.self, in: g)
        s.id = UUID(); s.name = name; s.place = place
        s.order = Int64((g.shelfList.map(\.order).max() ?? 0) + 1)
        s.group = g
        db.save()
    }

    // MARK: Avisos

    func show(_ message: String) {
        toast = message
        Haptics.success()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if toast == message { toast = nil }
        }
    }
}

enum AppTab: Hashable { case home, catalog, basket, pantry }

enum PantryPlace: String, CaseIterable, Identifiable {
    case despensa, nevera, congelador
    var id: String { rawValue }
    var title: String {
        switch self {
        case .despensa: "Despensa"
        case .nevera: "Nevera"
        case .congelador: "Congelador"
        }
    }
    var icon: String {
        switch self {
        case .despensa: "cabinet"
        case .nevera: "refrigerator"
        case .congelador: "snowflake"
        }
    }
}
