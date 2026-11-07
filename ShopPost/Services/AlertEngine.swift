import Foundation
import UserNotifications

/// Comprueba las alertas de ahorro con los datos nuevos y avisa con notificaciones locales.
@MainActor
final class AlertEngine {
    static let shared = AlertEngine()

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func matches(for alert: PriceAlert, catalog: CatalogService) -> [Product] {
        let storeSet: Set<String>? = alert.stores.isEmpty ? nil : Set(alert.stores)
        let terms = Text2.normalize(alert.query).split(separator: " ").map(String.init)

        func ok(_ p: Product) -> Bool {
            if let storeSet, !storeSet.contains(p.store) { return false }
            if let pid = alert.productId { return p.id == pid }
            return terms.allSatisfy { p.key.contains($0) }
        }

        var pool: [Product] = []
        let minDrop = Double(alert.minDrop)
        if alert.kind == .drop || alert.kind == .any {
            pool += catalog.changes.filter { ($0.pct ?? 0) < 0 && -($0.pct ?? 0) >= minDrop && ok($0) }
        }
        if alert.kind == .offer || alert.kind == .any {
            let source = alert.productId.flatMap { catalog.byId[$0] }.map { [$0] } ?? catalog.allProducts
            pool += source.filter { $0.isOnOffer && catalog.discount($0) * 100 >= minDrop && ok($0) }
        }
        if alert.kind == .new {
            pool += catalog.newProducts.filter(ok)
        }
        var seen = Set<String>()
        return pool.filter { seen.insert($0.id + "@\($0.price)").inserted }
    }

    func evaluate(catalog: CatalogService) {
        let prefs = Preferences.shared
        var newHits: [(PriceAlert, [Product])] = []
        for i in prefs.alerts.indices where prefs.alerts[i].enabled {
            let alert = prefs.alerts[i]
            let found = matches(for: alert, catalog: catalog)
            let keys = found.map { $0.id + "@\($0.price)" }
            let fresh = zip(found, keys).filter { !alert.seen.contains($0.1) }.map(\.0)
            if !fresh.isEmpty { newHits.append((alert, fresh)) }
            prefs.alerts[i].seen = Array(Set(alert.seen + keys).suffix(2000))
        }
        for (alert, products) in newHits.prefix(5) {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            let first = products[0]
            if products.count == 1 {
                content.body = "\(first.name): \(Money.string(first.price))"
            } else {
                content.body = "\(first.name) y \(products.count - 1) más coinciden con tu alerta."
            }
            content.sound = .default
            content.userInfo = ["alert": alert.id.uuidString]
            let req = UNNotificationRequest(identifier: alert.id.uuidString + "-" + first.id, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(req)
        }
    }
}
