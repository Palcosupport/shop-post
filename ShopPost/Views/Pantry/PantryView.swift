import SwiftUI

/// Despensa, nevera y congelador: lo que hay en casa y lo que falta.
struct PantryView: View {
    @Environment(ShopModel.self) private var shop
    @Environment(CatalogService.self) private var catalog
    @State private var place: PantryPlace = .despensa
    @State private var addingTo: SPShelf?
    @State private var addingNew = false
    @State private var newShelf = false
    @State private var shelfName = ""
    @State private var renaming: SPShelf?
    @State private var editingItem: SPPantryItem?

    var body: some View {
        let _ = shop.revision
        let group = shop.activeGroup
        let shelves = (group?.shelfList ?? []).filter { ($0.place ?? "despensa") == place.rawValue }
        let items = shop.pantryItems(in: group, place: place.rawValue)
        let missing = shop.missingPantry(in: group)
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .top) {
                    ScreenTitle(title: "En casa",
                                subtitle: "\(group?.title ?? "") · \(Count.items(group?.pantryList.count ?? 0, "producto", "productos"))\(missing.isEmpty ? "" : " · faltan \(missing.count)")")
                    CircleButton(systemName: "plus", filled: true, size: 60) { addingNew = true }
                        .accessibilityLabel("Añadir a la despensa")
                }
                HStack(spacing: 10) {
                    ForEach(PantryPlace.allCases) { p in
                        let count = shop.pantryItems(in: group, place: p.rawValue).count
                        Button { withAnimation(.snappy) { place = p }; Haptics.tap() } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Image(systemName: p.icon).font(.system(size: 21))
                                Text("\(count)").font(.system(size: 22, weight: .semibold))
                                Text(p.title).font(.spCaption)
                            }
                            .foregroundStyle(place == p ? Color.spOnInk : Color.spInk)
                            .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
                            .padding(16)
                            .background(place == p ? Color.spInk : Color.spCard, in: RoundedRectangle(cornerRadius: SPRadius.tile, style: .continuous))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }

                if !missing.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Qué falta").font(.spHeadline)
                                Text(missing.prefix(4).compactMap(\.name).joined(separator: ", "))
                                    .font(.spSub).foregroundStyle(Color.spSecondary).lineLimit(2)
                            }
                            Spacer()
                        }
                        PrimaryButton(title: "Añadir \(Count.items(missing.count)) a la cesta", systemName: "basket") {
                            shop.moveMissingToBasket(missing)
                        }
                    }
                    .spCard(padding: 20, radius: 30)
                }

                if items.isEmpty && shelves.allSatisfy({ $0.itemList.isEmpty }) {
                    EmptyCard(title: "Tu \(place.title.lowercased()) está vacía",
                              message: "Guarda lo que tienes en casa. Cuando algo se acabe, pásalo a la cesta con un toque.",
                              buttonTitle: "Añadir producto") { addingNew = true }
                }

                ForEach(shelves) { shelf in
                    shelfSection(shelf)
                }
                let loose = items.filter { $0.shelf == nil || ($0.shelf?.place ?? "") != place.rawValue }
                if !loose.isEmpty {
                    itemsRow(title: "Sin balda", items: loose, shelf: nil)
                }

                Button { shelfName = ""; newShelf = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                        Text("Añadir balda")
                    }
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.spInk)
                    .frame(maxWidth: .infinity).frame(height: 56)
                    .background(Color.spCardStrong, in: Capsule())
                }
                .buttonStyle(PressableStyle())
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, tabBarClearance)
        }
        .scrollIndicators(.hidden)
        .spScreen()
        .toolbarVisibility(.hidden, for: .navigationBar)
        .sheet(isPresented: $addingNew) { NavigationStack { PantryAddView(place: place, shelf: nil) }.spSheet() }
        .sheet(item: $addingTo) { x in NavigationStack { PantryAddView(place: place, shelf: x) }.spSheet() }
        .sheet(item: $editingItem) { x in NavigationStack { PantryItemEditor(item: x) }.spSheet().presentationDetents([.medium, .large]) }
        .alert("Nueva balda", isPresented: $newShelf) {
            TextField("Nombre", text: $shelfName)
            Button("Cancelar", role: .cancel) {}
            Button("Añadir") { shop.addShelf(name: shelfName.isEmpty ? "Balda" : shelfName, place: place.rawValue) }
        }
        .alert("Renombrar balda", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Nombre", text: $shelfName)
            Button("Cancelar", role: .cancel) {}
            Button("Guardar") { renaming?.name = shelfName; shop.db.save() }
        }
    }

    private func shelfSection(_ shelf: SPShelf) -> some View {
        itemsRow(title: shelf.name ?? "Balda", items: shelf.itemList.filter { ($0.place ?? "despensa") == place.rawValue }, shelf: shelf)
    }

    private func itemsRow(title: String, items: [SPPantryItem], shelf: SPShelf?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title).font(.spSection)
                Text("\(items.count)").font(.spSub).foregroundStyle(Color.spSecondary)
                Spacer()
                if let shelf {
                    Menu {
                        Button { addingTo = shelf } label: { Label("Añadir aquí", systemImage: "plus") }
                        Button { shelfName = shelf.name ?? ""; renaming = shelf } label: { Label("Renombrar", systemImage: "pencil") }
                        Button(role: .destructive) { shop.db.viewContext.delete(shelf); shop.db.save() } label: {
                            Label("Eliminar balda", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.spSecondary).frame(width: 40, height: 32)
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items) { item in
                        PantryCard(item: item)
                            .onTapGesture { editingItem = item }
                            .contextMenu {
                                Button { item.quantity += 1; shop.db.save() } label: { Label("Tengo una más", systemImage: "plus") }
                                if item.quantity > 0 {
                                    Button { item.quantity -= 1; shop.db.save() } label: { Label("He gastado una", systemImage: "minus") }
                                }
                                Button { item.quantity = 0; shop.db.save(); shop.moveMissingToBasket([item]) } label: {
                                    Label("Se acabó: a la cesta", systemImage: "basket")
                                }
                                Button { editingItem = item } label: { Label("Editar", systemImage: "pencil") }
                                Button(role: .destructive) { shop.db.viewContext.delete(item); shop.db.save() } label: {
                                    Label("Eliminar", systemImage: "trash")
                                }
                            }
                    }
                    Button { if let shelf { addingTo = shelf } else { addingNew = true } } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "plus").font(.system(size: 24, weight: .light))
                            Text("Añadir").font(.spCaption)
                        }
                        .foregroundStyle(Color.spSecondary)
                        .frame(width: 120, height: 172)
                        .background(Color.spCard, in: RoundedRectangle(cornerRadius: SPRadius.tile, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                }
                .padding(.horizontal, 20)
            }
            .scrollClipDisabled()
            .padding(.horizontal, -20)
            // Balda de madera estilizada (línea) bajo los productos.
            Capsule().fill(Color.spCardStrong).frame(height: 6)
        }
    }
}

struct PantryCard: View {
    @Environment(ShopModel.self) private var shop
    @Environment(CatalogService.self) private var catalog
    @ObservedObject var item: SPPantryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProductImage(url: item.imageURL, padding: 10, placeholderEmoji: catalog.category(item.cat ?? "")?.emoji ?? "🥫")
                .frame(width: 112, height: 88)
                .saturation(item.isMissing ? 0 : 1)
                .opacity(item.isMissing ? 0.5 : 1)
            Text(item.name ?? "").font(.system(size: 14, weight: .semibold)).lineLimit(2, reservesSpace: true)
            HStack(spacing: 6) {
                if item.isMissing {
                    Badge(text: "Falta")
                } else {
                    Text("\(item.quantity) ud").font(.spCaption).foregroundStyle(Color.spSecondary)
                }
                if let exp = item.expiry {
                    let soon = exp < Date().addingTimeInterval(3 * 86400)
                    Image(systemName: "calendar").font(.system(size: 11)).foregroundStyle(soon ? Color.spRed : Color.spSecondary)
                    Text(Day.relative(exp)).font(.system(size: 11)).foregroundStyle(soon ? Color.spRed : Color.spSecondary)
                }
            }
        }
        .foregroundStyle(Color.spInk)
        .padding(12)
        .frame(width: 136, height: 172, alignment: .topLeading)
        .background(Color.spCard, in: RoundedRectangle(cornerRadius: SPRadius.tile, style: .continuous))
    }
}

struct PantryItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ShopModel.self) private var shop
    @ObservedObject var item: SPPantryItem
    @State private var hasExpiry = false
    @State private var expiry = Date().addingTimeInterval(7 * 86400)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Thumb(url: item.imageURL, size: 64)
                    Text(item.name ?? "").font(.spTitle).lineLimit(2)
                }
                stepperRow("Cantidad en casa", value: Binding(get: { Int(item.quantity) }, set: { item.quantity = Int64(max(0, $0)) }))
                stepperRow("Avisar cuando queden menos de", value: Binding(get: { Int(item.minQuantity) }, set: { item.minQuantity = Int64(max(1, $0)) }))
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Fecha de caducidad", isOn: $hasExpiry).font(.spHeadline)
                    if hasExpiry {
                        DatePicker("Caduca", selection: $expiry, displayedComponents: .date)
                            .datePickerStyle(.compact)
                    }
                }
                .spCard(padding: 18, radius: SPRadius.tile)
                Picker("Lugar", selection: Binding(get: { item.place ?? "despensa" }, set: { newPlace in
                    item.place = newPlace
                    item.shelf = item.group?.shelfList.first { $0.place == newPlace }
                })) {
                    ForEach(PantryPlace.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                PrimaryButton(title: "Guardar") {
                    item.expiry = hasExpiry ? expiry : nil
                    shop.db.save()
                    dismiss()
                }
                if item.isMissing {
                    PrimaryButton(title: "Añadir a la cesta", systemName: "basket", style: .soft) {
                        shop.db.save(); shop.moveMissingToBasket([item]); dismiss()
                    }
                }
            }
            .padding(24)
        }
        .onAppear {
            hasExpiry = item.expiry != nil
            if let e = item.expiry { expiry = e }
        }
    }

    private func stepperRow(_ title: String, value: Binding<Int>) -> some View {
        HStack {
            Text(title).font(.spHeadline)
            Spacer()
            HStack(spacing: 0) {
                Button { value.wrappedValue -= 1 } label: { Image(systemName: "minus").frame(width: 40, height: 44) }
                Text("\(value.wrappedValue)").font(.spHeadline).monospacedDigit().frame(minWidth: 26)
                Button { value.wrappedValue += 1 } label: { Image(systemName: "plus").frame(width: 40, height: 44) }
            }
            .foregroundStyle(Color.spInk)
            .background(Color.spChip, in: Capsule())
        }
        .spCard(padding: 18, radius: SPRadius.tile)
    }
}

struct PantryAddView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ShopModel.self) private var shop
    @State var place: PantryPlace
    let shelf: SPShelf?
    @State private var name = ""
    @State private var product: Product?
    @State private var quantity = 1
    @State private var picking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Guardar en casa").font(.spTitle)
                Button { picking = true } label: {
                    if let product {
                        HStack(spacing: 12) {
                            Thumb(url: product.imageURL, size: 56)
                            VStack(alignment: .leading) {
                                Text(product.name).font(.spHeadline).lineLimit(2).multilineTextAlignment(.leading)
                                Text("Toca para cambiar").font(.spCaption).foregroundStyle(Color.spSecondary)
                            }
                            Spacer()
                        }
                        .foregroundStyle(Color.spInk)
                        .spCard(padding: 14, radius: SPRadius.tile)
                    } else {
                        OptionRow(icon: "magnifyingglass", title: "Buscar en el catálogo", subtitle: "Con foto y precio", circled: true)
                    }
                }
                .buttonStyle(PressableStyle())
                if product == nil {
                    TextField("O escribe el nombre (p. ej. Arroz)", text: $name)
                        .font(.spBody).padding(.horizontal, 20).frame(height: 56)
                        .background(Color.spChip, in: Capsule())
                }
                HStack {
                    Text("Cantidad").font(.spHeadline)
                    Spacer()
                    QuantityControl(quantity: quantity) { quantity = max(1, $0) }
                }
                .spCard(padding: 18, radius: SPRadius.tile)
                Picker("Lugar", selection: $place) {
                    ForEach(PantryPlace.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                PrimaryButton(title: "Guardar") {
                    shop.addToPantry(name: name, product: product, quantity: quantity, place: place.rawValue,
                                     shelf: shelf?.place == place.rawValue ? shelf : nil)
                    dismiss()
                }
                .disabled(product == nil && name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(24)
        }
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Image(systemName: "xmark") } } }
        .sheet(isPresented: $picking) {
            NavigationStack { ProductPicker(initialQuery: name) { product = $0 } }.spSheet()
        }
    }
}
