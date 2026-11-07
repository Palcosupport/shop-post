import SwiftUI

struct BasketView: View {
    @Environment(ShopModel.self) private var shop
    @Environment(CatalogService.self) private var catalog
    @Environment(Preferences.self) private var prefs
    @State private var filter = "all"
    @State private var collapsed: Set<String> = []
    @State private var noteItem: SPItem?
    @State private var showCompare = false
    @State private var showNewGroup = false
    @State private var editGroup: SPGroup?
    @State private var shareGroup: SPGroup?
    @State private var confirmClear = false

    var body: some View {
        let _ = shop.revision
        let group = shop.activeGroup
        let items = group?.itemList ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header(group, items)
                stats(group, items)
                groupsCarousel(group)
                if !items.isEmpty {
                    compareCard(items)
                    ChipBar(items: [("all", "Todo", nil), ("pending", "Pendiente", nil), ("done", "Recogido", nil)],
                            selection: $filter)
                    sections(items)
                } else {
                    EmptyCard(title: "La cesta está vacía",
                              message: "Añade productos desde el catálogo, escaneando un código o escribiéndolos a mano.",
                              buttonTitle: "Añadir productos") { shop.showAddSheet = true }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, items.isEmpty ? tabBarClearance : tabBarClearance + 84)
        }
        .scrollIndicators(.hidden)
        .spScreen()
        .toolbarVisibility(.hidden, for: .navigationBar)
        .overlay(alignment: .bottom) {
            if !items.isEmpty { totalBar(items).padding(.bottom, tabBarClearance - 8) }
        }
        .sheet(item: $noteItem) { x in NavigationStack { ItemNoteSheet(item: x) }.spSheet().presentationDetents([.medium, .large]) }
        .sheet(isPresented: $showCompare) { NavigationStack { CompareSheet(items: items) }.spSheet() }
        .sheet(isPresented: $showNewGroup) { NavigationStack { GroupEditor(group: nil) }.spSheet().presentationDetents([.medium]) }
        .sheet(item: $editGroup) { x in NavigationStack { GroupDetailView(group: x) }.spSheet() }
        .sheet(item: $shareGroup) { CloudShareView(group: $0).ignoresSafeArea() }
        .confirmationDialog("¿Qué quieres hacer con la cesta?", isPresented: $confirmClear, titleVisibility: .visible) {
            if let group, group.checkedCount > 0 {
                Button("Terminar compra (guardar \(group.checkedCount) recogidos)") { shop.finishShopping(in: group) }
            }
            if let group {
                Button("Vaciar toda la cesta", role: .destructive) { shop.clearAll(in: group) }
            }
        }
    }

    // MARK: Cabecera

    private func header(_ g: SPGroup?, _ items: [SPItem]) -> some View {
        HStack(alignment: .top) {
            ScreenTitle(title: "Mi cesta",
                        subtitle: "\(g?.title ?? "") · \(Count.items(items.count)) · \(Money.string(g?.total ?? 0))")
            HStack(spacing: 10) {
                if !items.isEmpty {
                    CircleButton(systemName: "ellipsis", size: 52) { confirmClear = true }
                }
                CircleButton(systemName: "person.badge.plus", filled: true, size: 60) {
                    if let g { shareGroup = g }
                }
                .accessibilityLabel("Invitar al grupo")
            }
        }
    }

    private func stats(_ g: SPGroup?, _ items: [SPItem]) -> some View {
        let done = items.filter(\.checked).count
        let members = g.map { max(1, Persistence.shared.participants(of: $0).count) } ?? 1
        let missing = items.filter(\.notInStore).count
        return HStack(spacing: 10) {
            StatTile(icon: "checkmark.circle", value: items.isEmpty ? "0 %" : "\(Int(Double(done) / Double(items.count) * 100)) %", label: "Recogido")
            StatTile(icon: missing > 0 ? "exclamationmark.circle" : "person.2", value: missing > 0 ? "\(missing)" : "\(members)",
                     label: missing > 0 ? "No estaban" : (members == 1 ? "Miembro" : "Miembros"))
            StatTile(icon: "eurosign", value: shortMoney(g?.total ?? 0), label: "Total")
        }
    }

    private func shortMoney(_ v: Double) -> String {
        v >= 100 ? String(format: "%.0f €", v) : Money.string(v)
    }

    // MARK: Grupos

    private func groupsCarousel(_ active: SPGroup?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Mis grupos")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(shop.groups()) { g in
                        GroupCard(group: g, active: g.objectID == active?.objectID)
                            .onTapGesture { withAnimation(.snappy) { shop.setActive(g) }; Haptics.tap() }
                            .contextMenu {
                                Button { editGroup = g } label: { Label("Gestionar grupo", systemImage: "slider.horizontal.3") }
                                Button { shareGroup = g } label: { Label("Invitar personas", systemImage: "person.badge.plus") }
                            }
                    }
                    Button { showNewGroup = true } label: {
                        VStack(spacing: 10) {
                            Image(systemName: "plus").font(.system(size: 28, weight: .light))
                            Text("Nuevo grupo").font(.spSub)
                        }
                        .foregroundStyle(Color.spSecondary)
                        .frame(width: 150, height: 170)
                        .background(Color.spCard, in: RoundedRectangle(cornerRadius: SPRadius.card, style: .continuous))
                    }
                    .buttonStyle(PressableStyle())
                }
                .padding(.horizontal, 20)
            }
            .scrollClipDisabled()
            .padding(.horizontal, -20)
        }
    }

    // MARK: Comparar

    private func compareCard(_ items: [SPItem]) -> some View {
        Button { showCompare = true } label: {
            HStack(spacing: 16) {
                Image(systemName: "chart.bar.xaxis").font(.system(size: 22))
                VStack(alignment: .leading, spacing: 3) {
                    Text("¿Dónde sale más barata?").font(.spHeadline)
                    Text("Compara tu cesta en todos tus supermercados").font(.spSub).foregroundStyle(Color.spSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.spTertiary)
            }
            .foregroundStyle(Color.spInk)
            .spCard(padding: 20)
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: Lista

    private func sections(_ items: [SPItem]) -> some View {
        let visible = items.filter { filter == "all" || (filter == "done") == $0.checked }
        let byStore = Dictionary(grouping: visible) { $0.store ?? "_none" }
        let storeOrder = byStore.keys.sorted { a, b in
            if a == "_none" { return false }
            if b == "_none" { return true }
            return (catalog.store(a)?.name ?? a) < (catalog.store(b)?.name ?? b)
        }
        return VStack(alignment: .leading, spacing: 22) {
            if visible.isEmpty {
                Text(filter == "done" ? "Todavía no has recogido nada." : "¡Lo tienes todo!")
                    .font(.spSub).foregroundStyle(Color.spSecondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
            }
            ForEach(storeOrder, id: \.self) { sid in
                let storeItems = byStore[sid] ?? []
                let all = items.filter { ($0.store ?? "_none") == sid }
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        withAnimation(.snappy) { if collapsed.contains(sid) { collapsed.remove(sid) } else { collapsed.insert(sid) } }
                    } label: {
                        HStack(spacing: 12) {
                            if sid == "_none" {
                                Image(systemName: "cart").frame(width: 30, height: 30)
                            } else {
                                StoreBadge(storeId: sid, size: 30)
                            }
                            Text(sid == "_none" ? "Sin supermercado" : (catalog.store(sid)?.name ?? sid.capitalized)).font(.spSection)
                            Spacer()
                            Text("\(all.filter(\.checked).count)/\(all.count)").font(.spSub).foregroundStyle(Color.spSecondary).monospacedDigit()
                            Image(systemName: "chevron.down")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.spTertiary)
                                .rotationEffect(.degrees(collapsed.contains(sid) ? -90 : 0))
                        }
                        .foregroundStyle(Color.spInk)
                    }
                    .buttonStyle(.plain)

                    if !collapsed.contains(sid) {
                        let byCat = Dictionary(grouping: storeItems) { $0.cat ?? "otros" }
                        let cats = catalog.categories.map(\.id).filter { byCat[$0] != nil } + byCat.keys.filter { id in !catalog.categories.contains { $0.id == id } }
                        ForEach(cats, id: \.self) { cat in
                            let info = catalog.category(cat)
                            Text("\(info?.emoji ?? "🛒")  \((info?.name ?? "Otros").uppercased())")
                                .font(.system(size: 12, weight: .semibold)).tracking(1.6)
                                .foregroundStyle(Color.spSecondary)
                                .padding(.top, 4)
                            ForEach(byCat[cat] ?? []) { item in
                                BasketItemRow(item: item, onNote: { noteItem = item })
                            }
                        }
                    }
                }
            }
        }
    }

    private func totalBar(_ items: [SPItem]) -> some View {
        let total = items.reduce(0) { $0 + $1.lineTotal }
        let pending = items.filter { !$0.checked }.reduce(0) { $0 + $1.lineTotal }
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Total estimado").font(.spSub).foregroundStyle(Color.spSecondary)
                if pending != total {
                    Text("Falta por recoger \(Money.string(pending))").font(.spCaption).foregroundStyle(Color.spSecondary)
                }
            }
            Spacer()
            Text(Money.string(total)).font(.system(size: 26, weight: .bold)).monospacedDigit()
        }
        .padding(.horizontal, 22)
        .frame(height: 70)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }
}

struct GroupCard: View {
    let group: SPGroup
    let active: Bool

    var body: some View {
        let items = group.itemList
        let shared = Persistence.shared.isShared(group)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(group.icon).font(.system(size: 44))
                Spacer()
                if active {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(Color.spInk)
                }
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: shared ? "person.2" : "basket").font(.system(size: 15))
                Text(group.title).font(.spHeadline).lineLimit(1)
            }
            Text("\(Count.items(items.count)) · \(Money.string(group.total))")
                .font(.spCaption).foregroundStyle(Color.spSecondary).padding(.top, 6)
        }
        .foregroundStyle(Color.spInk)
        .padding(18)
        .frame(width: 190, height: 170, alignment: .topLeading)
        .background(Color.spCard, in: RoundedRectangle(cornerRadius: SPRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: SPRadius.card, style: .continuous).stroke(Color.spInk, lineWidth: active ? 2 : 0))
    }
}

struct BasketItemRow: View {
    @Environment(ShopModel.self) private var shop
    @Environment(CatalogService.self) private var catalog
    @ObservedObject var item: SPItem
    let onNote: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button { withAnimation(.snappy) { shop.toggleChecked(item) } } label: {
                    Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(item.checked ? Color.spInk : Color.spTertiary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.checked ? "Recogido" : "Marcar como recogido")

                Thumb(url: item.imageURL, size: 58, emoji: catalog.category(item.cat ?? "")?.emoji ?? "🛒")
                    .onTapGesture { if let p = catalog.product(item.productId) { shop.presentedProduct = p } }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 16, weight: .semibold))
                        .strikethrough(item.checked)
                        .foregroundStyle(item.checked ? Color.spSecondary : Color.spInk)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text("\(item.quantity) ud").foregroundStyle(Color.spSecondary)
                        if item.price > 0 { Text(Money.string(item.lineTotal)).fontWeight(.semibold) }
                        if let current = catalog.product(item.productId), current.price != item.price {
                            Image(systemName: current.price < item.price ? "arrow.down" : "arrow.up")
                                .foregroundStyle(current.price < item.price ? Color.spGreen : Color.spRed)
                        }
                    }
                    .font(.spSub)
                }
                Spacer(minLength: 4)
                Menu {
                    Button { item.quantity += 1; shop.db.save() } label: { Label("Una más", systemImage: "plus") }
                    if item.quantity > 1 {
                        Button { item.quantity -= 1; shop.db.save() } label: { Label("Una menos", systemImage: "minus") }
                    }
                    Button(action: onNote) { Label("Notas y sustituto", systemImage: "text.bubble") }
                    Button { item.notInStore.toggle(); shop.db.save() } label: {
                        Label(item.notInStore ? "Sí estaba en la tienda" : "No estaba en la tienda", systemImage: "bookmark")
                    }
                    assignMenu
                    if let p = catalog.product(item.productId) {
                        Button { shop.presentedProduct = p } label: { Label("Buscar más económicos", systemImage: "magnifyingglass") }
                    }
                    Divider()
                    Button(role: .destructive) { withAnimation { shop.delete(item) } } label: { Label("Eliminar", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.spSecondary)
                        .frame(width: 40, height: 40)
                }
            }
            if hasExtras {
                VStack(alignment: .leading, spacing: 8) {
                    if let note = item.note, !note.isEmpty {
                        Label(note, systemImage: "text.bubble").font(.spCaption).foregroundStyle(Color.spSecondary)
                    }
                    if let sub = item.substituteName {
                        Label("Si no hay: \(sub)\(item.substitutePrice > 0 ? " · \(Money.string(item.substitutePrice))" : "")",
                              systemImage: "arrow.triangle.swap").font(.spCaption).foregroundStyle(Color.spSecondary)
                    }
                    HStack(spacing: 6) {
                        if item.notInStore { Badge(text: "No estaba en la tienda", icon: "bookmark.fill") }
                        if let a = item.assignee { Badge(text: a, color: .spInk, soft: .spCardStrong, icon: "person") }
                        if item.checked, let by = item.checkedBy { Badge(text: "Recogido por \(by)", color: .spGreen, soft: .spGreenSoft) }
                    }
                }
                .padding(.leading, 40)
            }
        }
        .padding(14)
        .background(Color.spCard, in: RoundedRectangle(cornerRadius: SPRadius.tile, style: .continuous))
        .opacity(item.checked ? 0.75 : 1)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { withAnimation(.snappy) { shop.toggleChecked(item) } }
    }

    private var hasExtras: Bool {
        (item.note?.isEmpty == false) || item.substituteName != nil || item.notInStore || item.assignee != nil || (item.checked && item.checkedBy != nil)
    }

    @ViewBuilder private var assignMenu: some View {
        let names = memberNames
        if !names.isEmpty {
            Menu {
                ForEach(names, id: \.self) { n in
                    Button { item.assignee = n; shop.db.save() } label: {
                        Label(n, systemImage: item.assignee == n ? "checkmark" : "person")
                    }
                }
                if item.assignee != nil {
                    Button("Sin asignar") { item.assignee = nil; shop.db.save() }
                }
            } label: { Label("Asignar a…", systemImage: "person.crop.circle.badge.plus") }
        }
    }

    private var memberNames: [String] {
        var names: [String] = []
        if let g = item.group {
            for p in Persistence.shared.participants(of: g) {
                if let c = p.userIdentity.nameComponents {
                    let n = PersonNameComponentsFormatter.localizedString(from: c, style: .short)
                    if !n.isEmpty { names.append(n) }
                }
            }
        }
        let me = Preferences.shared.userName
        if !me.isEmpty, !names.contains(me) { names.insert(me, at: 0) }
        return names
    }
}
