import Foundation

/// Producto normalizado tal y como lo publica el servidor (server/common.py → make_product).
struct Product: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let store: String
    let sku: String?
    let name: String
    let brand: String?
    let cat: String
    let category: String?
    let subcategory: String?
    let price: Double
    let unitPrice: Double?
    let unit: String?
    let size: String?
    let image: String?
    let previousPrice: Double?
    let promo: String?
    let ean: String?
    let url: String?
    // Historial (añadido por run.py)
    let lastPrice: Double?
    let changedAt: String?
    let firstSeen: String?
    // Solo en changes.json / new.json
    let oldPrice: Double?
    let pct: Double?
    let date: String?

    /// Texto normalizado para búsquedas (sin acentos, minúsculas). Se rellena al cargar.
    var key: String = ""

    enum CodingKeys: String, CodingKey {
        case id, store, sku, name, brand, cat, category, subcategory, price, unitPrice, unit, size, image,
             previousPrice, promo, ean, url, lastPrice, changedAt, firstSeen, oldPrice, pct, date
    }

    static func == (a: Product, b: Product) -> Bool { a.id == b.id && a.price == b.price }
    func hash(into h: inout Hasher) { h.combine(id) }

    var imageURL: URL? { image.flatMap(URL.init(string:)) }
    var webURL: URL? { url.flatMap(URL.init(string:)) }

    /// Precio anterior a mostrar tachado: oferta de la tienda o último precio distinto si ha bajado.
    var strikePrice: Double? {
        if let p = previousPrice, p > price { return p }
        if let o = oldPrice ?? lastPrice, o > price, isRecentChange { return o }
        return nil
    }

    var isOnOffer: Bool { (previousPrice ?? 0) > price || promo != nil }

    var changePercent: Double? {
        if let pct { return pct }
        guard let lastPrice, lastPrice > 0, isRecentChange else { return nil }
        return (price - lastPrice) / lastPrice * 100
    }

    var isRecentChange: Bool {
        guard let d = changedAt ?? date, let day = Day.parse(d) else { return false }
        return day > Date().addingTimeInterval(-14 * 86400)
    }

    var subtitle: String {
        [size, Money.unitString(unitPrice, unit: unit)].compactMap { $0 }.joined(separator: " · ")
    }
}

struct StoreInfo: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let color: String?
    let web: String?
    let status: String?
    let count: Int?
    let updatedAt: String?
    let error: String?

    var isAvailable: Bool { status == "ok" || (count ?? 0) > 0 }
}

struct CategoryInfo: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let emoji: String
}

struct CatalogMeta: Codable, Sendable {
    let version: Int?
    let updatedAt: String?
    let stores: [StoreInfo]
    let categories: [CategoryInfo]
}

struct StoreFile: Codable, Sendable {
    let store: String
    let updatedAt: String?
    var products: [Product]
}

struct FeedFile: Codable, Sendable {
    let updatedAt: String?
    var items: [Product]
}

enum Day {
    static let isoDay: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func parse(_ s: String) -> Date? {
        if s.count >= 10, let d = isoDay.date(from: String(s.prefix(10))) { return d }
        return nil
    }

    static func parseTimestamp(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s) ?? parse(s)
    }

    static func relative(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "hoy" }
        if cal.isDateInYesterday(date) { return "ayer" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "d MMM"
        return f.string(from: date)
    }
}

enum Text2 {
    /// Minúsculas, sin acentos ni signos: base de búsqueda y comparación.
    static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
        var out = ""
        out.reserveCapacity(folded.count)
        for ch in folded {
            if ch.isLetter || ch.isNumber { out.append(ch) } else { out.append(" ") }
        }
        return out.split(separator: " ").joined(separator: " ")
    }

    static let stopwords: Set<String> = ["de", "del", "la", "el", "los", "las", "con", "sin", "en", "y", "a", "al",
                                         "para", "por", "x", "pack", "ud", "uds", "unidad", "unidades", "g", "gr",
                                         "kg", "ml", "cl", "l", "lt", "bote", "botella", "lata", "paquete", "bolsa",
                                         "brik", "tarrina", "bandeja", "caja", "frasco", "envase"]

    static func tokens(_ s: String) -> [String] {
        normalize(s).split(separator: " ").map(String.init).filter { $0.count > 1 && !stopwords.contains($0) && Int($0) == nil }
    }
}
