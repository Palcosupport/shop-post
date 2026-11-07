import Foundation

/// Busca productos equivalentes entre supermercados (mismo tipo de producto, por nombre).
enum Matching {
    static func score(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        let inter = Double(a.intersection(b).count)
        return inter / Double(min(a.count, b.count)) * 0.7 + inter / Double(a.union(b).count) * 0.3
    }

    /// Tokens "de producto": quita la marca para comparar marcas blancas con marcas.
    static func productTokens(_ p: Product) -> Set<String> {
        var t = Set(Text2.tokens(p.name))
        if let brand = p.brand { t.subtract(Text2.tokens(brand)) }
        return t
    }

    /// Cada súper clasifica a su manera: solo se exige que ambos sean «comida» o ambos «no comida».
    static let nonFood: Set<String> = ["higiene-belleza", "limpieza-hogar", "mascotas"]

    static func compatible(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b else { return true }
        return nonFood.contains(a) == nonFood.contains(b)
    }

    static func comparablePrice(_ p: Product, like ref: Product) -> Double {
        if let u = p.unitPrice, let ru = ref.unitPrice, u > 0, ru > 0, p.unit == ref.unit { return u }
        return p.price
    }

    static func alternatives(to product: Product, in catalog: [String: [Product]], limit: Int) -> [Product] {
        let ref = productTokens(product)
        guard !ref.isEmpty else { return [] }
        var scored: [(Product, Double)] = []
        for list in catalog.values {
            for p in list where p.id != product.id && compatible(p.cat, product.cat) {
                if let u = product.unit, let pu = p.unit, u != pu { continue }
                let s = score(ref, productTokens(p)) + (p.cat == product.cat ? 0.05 : 0)
                if s >= 0.55 { scored.append((p, s)) }
            }
        }
        // Mejor coincidencia por supermercado, ordenadas por precio comparable.
        var bestPerStore: [String: [(Product, Double)]] = [:]
        for item in scored.sorted(by: { $0.1 > $1.1 }) {
            if bestPerStore[item.0.store, default: []].count < 3 { bestPerStore[item.0.store, default: []].append(item) }
        }
        return bestPerStore.values.flatMap { $0.map(\.0) }
            .sorted { comparablePrice($0, like: product) < comparablePrice($1, like: product) }
            .prefix(limit).map { $0 }
    }

    /// Mejor equivalente de un producto en una tienda concreta (para comparar la cesta entera).
    static func bestMatch(name: String, brand: String?, cat: String?, unit: String?, in list: [Product]) -> Product? {
        var ref = Set(Text2.tokens(name))
        if let brand { ref.subtract(Text2.tokens(brand)) }
        guard !ref.isEmpty else { return nil }
        var best: (Product, Double)?
        for p in list {
            guard compatible(p.cat, cat) else { continue }
            if let unit, let pu = p.unit, unit != pu { continue }
            let s = score(ref, productTokens(p)) + (p.cat == cat ? 0.05 : 0)
            guard s >= 0.6 else { continue }
            if let b = best {
                if s > b.1 + 0.05 || (abs(s - b.1) <= 0.05 && p.price < b.0.price) { best = (p, s) }
            } else {
                best = (p, s)
            }
        }
        return best?.0
    }
}
