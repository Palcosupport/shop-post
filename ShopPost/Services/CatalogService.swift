import Foundation
import Observation

/// Descarga y guarda en caché los catálogos que publica el servidor (GitHub Pages).
@Observable
@MainActor
final class CatalogService {
    static let shared = CatalogService()

    /// URL pública de los datos. Se puede cambiar en Ajustes.
    static let defaultDataURL = "https://palcosupport.github.io/shop-post/data/"

    enum LoadState: Equatable { case idle, loading, loaded, failed(String) }

    private(set) var meta: CatalogMeta?
    private(set) var stores: [StoreInfo] = []
    private(set) var categories: [CategoryInfo] = []
    private(set) var productsByStore: [String: [Product]] = [:]
    private(set) var byId: [String: Product] = [:]
    private(set) var byEAN: [String: [Product]] = [:]
    private(set) var changes: [Product] = []
    private(set) var newProducts: [Product] = []
    /// Ofertas de todas las tiendas, ordenadas por descuento (se calcula una vez al cargar).
    private(set) var offerList: [Product] = []
    private(set) var state: LoadState = .idle
    private(set) var lastUpdate: Date?
    var progress: String = ""

    var dataURLString: String {
        get { UserDefaults.standard.string(forKey: "dataURL") ?? Self.initialDataURL }
        set { UserDefaults.standard.set(newValue, forKey: "dataURL") }
    }

    private static var initialDataURL: String {
        #if DEBUG && targetEnvironment(simulator)
        // En el simulador: datos generados en el Mac y servidos con
        // `python3 -m http.server 8765` desde la carpeta docs/.
        return "http://localhost:8765/data/"
        #else
        return defaultDataURL
        #endif
    }

    private var baseURL: URL? {
        var s = dataURLString.trimmingCharacters(in: .whitespaces)
        if !s.hasSuffix("/") { s += "/" }
        return URL(string: s)
    }

    private let cacheDir: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "catalog")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    var allProducts: [Product] { productsByStore.values.flatMap { $0 } }
    var totalCount: Int { productsByStore.values.reduce(0) { $0 + $1.count } }

    func store(_ id: String) -> StoreInfo? { stores.first { $0.id == id } }
    func category(_ id: String) -> CategoryInfo? { categories.first { $0.id == id } }
    func product(_ id: String?) -> Product? { id.flatMap { byId[$0] } }

    // MARK: - Carga

    /// Carga primero la caché local (inmediato) y luego actualiza desde la red.
    func bootstrap() async {
        if productsByStore.isEmpty { await loadFromCache() }
        await refresh()
    }

    func refresh(force: Bool = false) async {
        guard state != .loading, let baseURL else { return }
        state = .loading
        progress = "Buscando precios nuevos…"
        do {
            let metaData = try await fetch(baseURL.appending(path: "meta.json"))
            let newMeta = try JSONDecoder().decode(CatalogMeta.self, from: metaData)
            let cachedMeta = (try? Data(contentsOf: cacheDir.appending(path: "meta.json")))
                .flatMap { try? JSONDecoder().decode(CatalogMeta.self, from: $0) }

            var loaded = productsByStore
            for store in newMeta.stores where (store.count ?? 0) > 0 {
                let cachedStamp = cachedMeta?.stores.first { $0.id == store.id }?.updatedAt
                let cacheFile = cacheDir.appending(path: "\(store.id).json")
                let haveCache = FileManager.default.fileExists(atPath: cacheFile.path)
                if !force, haveCache, cachedStamp == store.updatedAt, loaded[store.id] != nil { continue }
                progress = "Actualizando \(store.name)…"
                let data = try await fetch(baseURL.appending(path: "\(store.id).json"))
                try? data.write(to: cacheFile, options: .atomic)
                loaded[store.id] = try await Self.decodeStore(data)
            }
            for name in ["changes", "new"] {
                if let data = try? await fetch(baseURL.appending(path: "\(name).json")) {
                    try? data.write(to: cacheDir.appending(path: "\(name).json"), options: .atomic)
                }
            }
            try? metaData.write(to: cacheDir.appending(path: "meta.json"), options: .atomic)
            apply(meta: newMeta, products: loaded)
            await loadFeedsFromCache()
            lastUpdate = Day.parseTimestamp(newMeta.updatedAt) ?? Date()
            state = .loaded
            progress = ""
            AlertEngine.shared.evaluate(catalog: self)
        } catch {
            progress = ""
            state = productsByStore.isEmpty ? .failed(Self.describe(error)) : .loaded
        }
    }

    private func loadFromCache() async {
        guard let data = try? Data(contentsOf: cacheDir.appending(path: "meta.json")),
              let cachedMeta = try? JSONDecoder().decode(CatalogMeta.self, from: data) else { return }
        var loaded: [String: [Product]] = [:]
        for store in cachedMeta.stores {
            let file = cacheDir.appending(path: "\(store.id).json")
            if let d = try? Data(contentsOf: file), let products = try? await Self.decodeStore(d) {
                loaded[store.id] = products
            }
        }
        apply(meta: cachedMeta, products: loaded)
        await loadFeedsFromCache()
        lastUpdate = Day.parseTimestamp(cachedMeta.updatedAt)
        if !loaded.isEmpty { state = .loaded }
    }

    private func loadFeedsFromCache() async {
        func feed(_ name: String) async -> [Product] {
            guard let d = try? Data(contentsOf: cacheDir.appending(path: "\(name).json")) else { return [] }
            return await Task.detached(priority: .userInitiated) {
                guard var f = try? JSONDecoder().decode(FeedFile.self, from: d) else { return [Product]() }
                for i in f.items.indices { f.items[i].key = Text2.normalize(f.items[i].name + " " + (f.items[i].brand ?? "")) }
                return f.items
            }.value
        }
        changes = await feed("changes")
        newProducts = await feed("new")
    }

    private func apply(meta: CatalogMeta, products: [String: [Product]]) {
        self.meta = meta
        stores = meta.stores
        categories = meta.categories
        productsByStore = products
        var ids: [String: Product] = [:]
        var eans: [String: [Product]] = [:]
        for list in products.values {
            for p in list {
                ids[p.id] = p
                if let e = p.ean, !e.isEmpty { eans[Self.normalizeEAN(e), default: []].append(p) }
            }
        }
        byId = ids
        byEAN = eans
        offerList = products.values.flatMap { $0.filter(\.isOnOffer) }.sorted { discount($0) > discount($1) }
    }

    nonisolated private static func decodeStore(_ data: Data) async throws -> [Product] {
        try await Task.detached(priority: .userInitiated) {
            var file = try JSONDecoder().decode(StoreFile.self, from: data)
            for i in file.products.indices {
                let p = file.products[i]
                file.products[i].key = Text2.normalize(p.name + " " + (p.brand ?? "") + " " + (p.subcategory ?? ""))
            }
            return file.products
        }.value
    }

    private func fetch(_ url: URL) async throws -> Data {
        if url.isFileURL { return try Data(contentsOf: url) }
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadRevalidatingCacheData
        req.timeoutInterval = 60
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Error \(http.statusCode) al descargar \(url.lastPathComponent)"])
        }
        return data
    }

    static func normalizeEAN(_ s: String) -> String {
        let digits = s.filter(\.isNumber)
        return digits.count == 13 && digits.hasPrefix("0") ? String(digits.dropFirst()) : digits
    }

    private static func describe(_ error: Error) -> String {
        if let u = error as? URLError, u.code == .notConnectedToInternet { return "Sin conexión a internet." }
        return error.localizedDescription
    }

    // MARK: - Consultas

    func search(_ query: String, stores storeIDs: Set<String>? = nil, category: String? = nil, limit: Int = 400) -> [Product] {
        let q = Text2.normalize(query).split(separator: " ").map(String.init)
        var out: [Product] = []
        for (sid, list) in productsByStore where storeIDs == nil || storeIDs!.contains(sid) {
            for p in list {
                if let category, p.cat != category { continue }
                if q.isEmpty || q.allSatisfy({ p.key.contains($0) }) { out.append(p) }
            }
        }
        if !q.isEmpty {
            // Primero los que empiezan por la búsqueda, luego los más baratos.
            let first = q[0]
            out.sort { a, b in
                let ha = a.key.hasPrefix(first), hb = b.key.hasPrefix(first)
                if ha != hb { return ha }
                return a.name.count < b.name.count
            }
        }
        return Array(out.prefix(limit))
    }

    func offers(stores storeIDs: Set<String>?) -> [Product] {
        offerList.filter { p in storeIDs == nil || storeIDs!.contains(p.store) }
    }

    func discount(_ p: Product) -> Double {
        guard let prev = p.previousPrice, prev > 0 else { return 0 }
        return (prev - p.price) / prev
    }

    func feedChanges(stores storeIDs: Set<String>?, drops: Bool) -> [Product] {
        changes.filter { c in
            (storeIDs == nil || storeIDs!.contains(c.store)) && ((c.pct ?? 0) < 0) == drops && c.pct != 0
        }
    }

    func feedNew(stores storeIDs: Set<String>?) -> [Product] {
        newProducts.filter { storeIDs == nil || storeIDs!.contains($0.store) }
    }

    /// Productos equivalentes (en cualquier supermercado) ordenados por precio por unidad.
    func alternatives(to product: Product, limit: Int = 12) async -> [Product] {
        let catalog = productsByStore
        return await Task.detached(priority: .userInitiated) {
            Matching.alternatives(to: product, in: catalog, limit: limit)
        }.value
    }
}
