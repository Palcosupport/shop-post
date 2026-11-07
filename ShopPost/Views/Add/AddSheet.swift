import SwiftUI
import VisionKit

/// Hoja del botón central «+».
struct AddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ShopModel.self) private var shop
    @State private var scanning = false
    @State private var manual = false
    @State private var pantry = false
    @State private var history = false
    @State private var scanned: ScannedResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Añadir").font(.title2.weight(.semibold))
                Text("A la cesta «\(shop.activeGroup?.title ?? "")» o a tu despensa.")
                    .font(.spSub).foregroundStyle(Color.spSecondary)
            }
            .padding(.bottom, 4)
            row("magnifyingglass", "Buscar en el catálogo", "Productos y precios") {
                dismiss()
                shop.tab = .catalog
                shop.catalogFocusSearch = true
            }
            row("barcode.viewfinder", "Escanear código", "Usa la cámara") { scanning = true }
            row("pencil.line", "Escribir a mano", "Aunque no esté en el catálogo") { manual = true }
            row("cabinet", "Guardar en la despensa", "Lo que ya tienes en casa") { pantry = true }
            row("clock.arrow.circlepath", "Repetir una compra", "Una lista anterior") { history = true }
            Button { dismiss() } label: {
                Text("Cancelar")
                    .font(.body)
                    .foregroundStyle(Color.spInk)
                    .frame(maxWidth: .infinity).frame(minHeight: 44)
                    .background(Color.spCardStrong, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(PressableStyle())
            .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .presentationDetents([.height(520), .large])
        .presentationDragIndicator(.visible)
        .fullScreenCover(isPresented: $scanning) {
            BarcodeScannerView { code in
                scanning = false
                Task { scanned = await ScannedResult.resolve(code) }
            }
        }
        .sheet(item: $scanned) { result in
            NavigationStack { ScanResultView(result: result) }.spSheet()
        }
        .sheet(isPresented: $manual) { NavigationStack { ManualItemView() }.spSheet().presentationDetents([.large]) }
        .sheet(isPresented: $pantry) { NavigationStack { PantryAddView(place: .despensa, shelf: nil) }.spSheet() }
        .sheet(isPresented: $history) { NavigationStack { HistoryView(closable: true) }.spSheet() }
    }

    private func row(_ icon: String, _ title: String, _ subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { OptionRow(icon: icon, title: title, subtitle: subtitle, circled: true) }
            .buttonStyle(PressableStyle())
    }
}

// MARK: - Escáner

struct ScannedResult: Identifiable {
    let id = UUID()
    let code: String
    let products: [Product]
    let facts: FoodFacts?

    @MainActor
    static func resolve(_ code: String) async -> ScannedResult {
        let catalog = CatalogService.shared
        let key = CatalogService.normalizeEAN(code)
        let exact = catalog.byEAN[key] ?? []
        let facts = await OpenFoodFacts.lookup(ean: code)
        var products = exact
        if let name = facts?.productName, !name.isEmpty {
            // Mismo producto en otros supermercados (por nombre).
            let q = Text2.tokens(name + " " + (facts?.brands ?? "")).prefix(4).joined(separator: " ")
            let similar = catalog.search(q, limit: 30).filter { p in !products.contains { $0.id == p.id } }
            products += similar.prefix(10)
        }
        return ScannedResult(code: code, products: products, facts: facts)
    }
}

struct ScanResultView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ShopModel.self) private var shop
    let result: ScannedResult

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let facts = result.facts {
                    HStack(spacing: 14) {
                        Thumb(url: facts.imageURL.flatMap(URL.init(string:)), size: 72)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(facts.productName ?? "Producto").font(.spTitle).lineLimit(2)
                            Text([facts.brands, facts.quantity].compactMap { $0 }.joined(separator: " · "))
                                .font(.spSub).foregroundStyle(Color.spSecondary)
                        }
                    }
                } else {
                    Text("Código \(result.code)").font(.spTitle)
                }
                if result.products.isEmpty {
                    EmptyCard(title: "No está en el catálogo",
                              message: "Puedes añadirlo igualmente a tu cesta escribiendo su nombre.",
                              buttonTitle: "Añadir \(result.facts?.productName ?? "a mano")") {
                        shop.addManual(name: result.facts?.productName ?? "Código \(result.code)", quantity: 1, store: nil, price: 0,
                                       image: result.facts?.imageURL)
                        dismiss()
                    }
                } else {
                    SectionHeader(title: "En tus supermercados")
                    ForEach(result.products.sorted { $0.price < $1.price }) { p in
                        ProductRow(product: p, showStore: true)
                    }
                }
            }
            .padding(20)
        }
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Image(systemName: "xmark") } } }
    }
}

struct BarcodeScannerView: View {
    @Environment(\.dismiss) private var dismiss
    let onCode: (String) -> Void
    @State private var manualCode = ""

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                ScannerRepresentable(onCode: onCode).ignoresSafeArea()
                // Marco de esquinas
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .trim(from: 0, to: 1)
                    .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [40, 1000]))
                    .frame(width: 280, height: 180)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "barcode.viewfinder").font(.largeTitle).foregroundStyle(.white)
                    Text("El escáner no está disponible en este dispositivo.\nEscribe el código:")
                        .multilineTextAlignment(.center).foregroundStyle(.white)
                    TextField("8410000000000", text: $manualCode)
                        .keyboardType(.numberPad)
                        .padding().background(.white, in: Capsule()).frame(width: 260)
                    Button("Buscar") { if !manualCode.isEmpty { onCode(manualCode) } }
                        .foregroundStyle(.black).padding(.horizontal, 28).frame(height: 48).background(.white, in: Capsule())
                }
            }
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.title3.weight(.semibold)).foregroundStyle(.white)
                            .frame(width: 48, height: 48).background(.ultraThinMaterial, in: Circle())
                    }
                    Spacer()
                }
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text("Apunta al código de barras")
                }
                .font(.subheadline.weight(.medium)).foregroundStyle(.white)
                .padding(.horizontal, 18).frame(height: 44).background(.ultraThinMaterial, in: Capsule())
            }
            .padding(16)
        }
    }
}

struct ScannerRepresentable: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])],
                                           qualityLevel: .balanced, recognizesMultipleItems: false,
                                           isHighFrameRateTrackingEnabled: false, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        var done = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in items {
                if case .barcode(let b) = item, let code = b.payloadStringValue {
                    done = true
                    scanner.stopScanning()
                    Haptics.success()
                    onCode(code)
                    return
                }
            }
        }
    }
}

// MARK: - Alta manual

struct ManualItemView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ShopModel.self) private var shop
    @Environment(CatalogService.self) private var catalog
    @Environment(Preferences.self) private var prefs
    @State private var name = ""
    @State private var quantity = 1
    @State private var store: String?
    @State private var price = ""
    @FocusState private var focused: Bool

    var body: some View {
        let suggestions = name.count < 3 ? [] : catalog.search(name, stores: Set(prefs.visibleStores(in: catalog).map(\.id)), limit: 6)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Escribir a mano").font(.spTitle)
                TextField("¿Qué falta? (p. ej. Leche)", text: $name)
                    .focused($focused)
                    .font(.spBody).padding(.horizontal, 14).frame(minHeight: 44)
                    .background(Color.spChip, in: Capsule())
                if !suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SUGERENCIAS DEL CATÁLOGO").font(.caption.weight(.semibold)).tracking(1.4).foregroundStyle(Color.spSecondary)
                        ForEach(suggestions) { p in
                            Button { shop.add(p, quantity: quantity); dismiss() } label: {
                                HStack(spacing: 12) {
                                    Thumb(url: p.imageURL, size: 44)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(p.name).font(.subheadline.weight(.medium)).lineLimit(1)
                                        StoreName(storeId: p.store)
                                    }
                                    Spacer()
                                    Text(Money.string(p.price)).font(.spSub.weight(.semibold))
                                }
                                .foregroundStyle(Color.spInk)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .spCard(padding: 16, radius: SPRadius.tile)
                }
                HStack {
                    Text("Cantidad").font(.spHeadline)
                    Spacer()
                    QuantityControl(quantity: quantity) { quantity = max(1, $0) }
                }
                .spCard(padding: 18, radius: SPRadius.tile)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Supermercado (opcional)").font(.spHeadline)
                    ChipBar(items: [("", "Cualquiera", nil)] + prefs.visibleStores(in: catalog).map { ($0.id, $0.name, nil) },
                            selection: Binding(get: { store ?? "" }, set: { store = $0.isEmpty ? nil : $0 }))
                }
                TextField("Precio aproximado (opcional)", text: $price)
                    .keyboardType(.decimalPad)
                    .font(.spBody).padding(.horizontal, 14).frame(minHeight: 44)
                    .background(Color.spChip, in: Capsule())
                PrimaryButton(title: "Añadir a la cesta", systemName: "basket") {
                    shop.addManual(name: name, quantity: quantity, store: store,
                                   price: Double(price.replacingOccurrences(of: ",", with: ".")) ?? 0)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Image(systemName: "xmark") } } }
        .onAppear { focused = true }
    }
}
