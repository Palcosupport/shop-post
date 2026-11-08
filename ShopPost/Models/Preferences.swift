import Foundation
import Observation

/// Alerta de ahorro definida por el usuario.
struct PriceAlert: Codable, Identifiable, Hashable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case drop, offer, new, any
        var id: String { rawValue }
        var label: String {
            switch self {
            case .drop: "Bajadas de precio"
            case .offer: "Ofertas"
            case .new: "Novedades"
            case .any: "Bajadas y ofertas"
            }
        }
        var short: String {
            switch self {
            case .drop: "Bajadas"
            case .offer: "Ofertas"
            case .new: "Novedades"
            case .any: "Mixta"
            }
        }
        var icon: String {
            switch self {
            case .drop: "chart.line.downtrend.xyaxis"
            case .offer: "tag"
            case .new: "sparkles"
            case .any: "bell"
            }
        }
    }

    var id = UUID()
    var kind: Kind = .any
    var query: String = ""
    var productId: String?
    var productName: String?
    var minDrop: Int = 0
    var stores: [String] = []
    var enabled = true
    var createdAt = Date()
    var seen: [String] = []

    var title: String {
        if let productName { return "\(kind.short) · \(productName)" }
        return query.isEmpty ? kind.label : "\(kind.short) · \(query)"
    }
}

struct PurchaseRecord: Codable, Identifiable, Hashable {
    struct Line: Codable, Hashable {
        var productId: String?
        var name: String
        var store: String?
        var image: String?
        var price: Double
        var quantity: Int
        var cat: String?
    }
    var id = UUID()
    var date = Date()
    var groupName: String
    var lines: [Line]
    var total: Double { lines.reduce(0) { $0 + $1.price * Double($1.quantity) } }
}

/// Preferencias locales del dispositivo (no se comparten).
@Observable
@MainActor
final class Preferences {
    static let shared = Preferences()

    var userName: String { didSet { save("userName", userName) } }
    var favoriteStores: [String] { didSet { save("favoriteStores", favoriteStores) } }
    var defaultStore: String? { didSet { save("defaultStore", defaultStore) } }
    var favorites: [String] { didSet { save("favorites", favorites) } }
    var alerts: [PriceAlert] { didSet { save("alerts", alerts) } }
    var history: [PurchaseRecord] { didSet { save("history", history) } }
    var gridView: Bool { didSet { save("gridView", gridView) } }
    var activeGroupID: String? { didSet { save("activeGroupID", activeGroupID) } }
    var onboarded: Bool { didSet { save("onboarded", onboarded) } }
    var accent: AccentChoice { didSet { save("accent", accent) } }

    private init() {
        userName = Self.load("userName") ?? ""
        favoriteStores = Self.load("favoriteStores") ?? []
        defaultStore = Self.load("defaultStore") ?? nil
        favorites = Self.load("favorites") ?? []
        alerts = Self.load("alerts") ?? []
        history = Self.load("history") ?? []
        gridView = Self.load("gridView") ?? true
        activeGroupID = Self.load("activeGroupID") ?? nil
        onboarded = Self.load("onboarded") ?? false
        accent = Self.load("accent") ?? .ink
    }

    var displayName: String { userName.isEmpty ? "tú" : userName }

    var initials: String {
        let parts = userName.split(separator: " ").prefix(2)
        let s = parts.compactMap(\.first).map(String.init).joined()
        return s.isEmpty ? "" : s.uppercased()
    }

    /// Supermercados visibles: los favoritos, o todos si no hay favoritos.
    func visibleStores(in catalog: CatalogService) -> [StoreInfo] {
        let available = catalog.stores.filter { $0.isAvailable }
        guard !favoriteStores.isEmpty else { return available }
        let favs = available.filter { favoriteStores.contains($0.id) }
        return favs.isEmpty ? available : favs
    }

    func isFavorite(_ id: String) -> Bool { favorites.contains(id) }

    func toggleFavorite(_ id: String) {
        if let i = favorites.firstIndex(of: id) { favorites.remove(at: i) } else { favorites.insert(id, at: 0) }
    }

    private func save<T: Encodable>(_ key: String, _ value: T) {
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: "pref." + key)
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        guard let d = UserDefaults.standard.data(forKey: "pref." + key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }
}
