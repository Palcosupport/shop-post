import CloudKit
import CoreData
import UIKit

// MARK: - Entidades (se sincronizan y comparten con iCloud)

@objc(SPGroup)
final class SPGroup: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var emoji: String?
    @NSManaged var createdAt: Date?
    @NSManaged var items: NSSet?
    @NSManaged var shelves: NSSet?
    @NSManaged var pantry: NSSet?

    var title: String { (name?.isEmpty == false ? name : nil) ?? "Mi grupo" }
    var icon: String { (emoji?.isEmpty == false ? emoji : nil) ?? "🛒" }
    var itemList: [SPItem] { (items?.allObjects as? [SPItem] ?? []).sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) } }
    var shelfList: [SPShelf] { (shelves?.allObjects as? [SPShelf] ?? []).sorted { $0.order < $1.order } }
    var pantryList: [SPPantryItem] { pantry?.allObjects as? [SPPantryItem] ?? [] }
    var total: Double { itemList.reduce(0) { $0 + $1.lineTotal } }
    var checkedCount: Int { itemList.filter(\.checked).count }
}

@objc(SPItem)
final class SPItem: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var productId: String?
    @NSManaged var store: String?
    @NSManaged var name: String?
    @NSManaged var brand: String?
    @NSManaged var image: String?
    @NSManaged var price: Double
    @NSManaged var size: String?
    @NSManaged var unit: String?
    @NSManaged var unitPrice: Double
    @NSManaged var cat: String?
    @NSManaged var quantity: Int64
    @NSManaged var checked: Bool
    @NSManaged var checkedBy: String?
    @NSManaged var note: String?
    @NSManaged var substituteId: String?
    @NSManaged var substituteName: String?
    @NSManaged var substitutePrice: Double
    @NSManaged var substituteImage: String?
    @NSManaged var notInStore: Bool
    @NSManaged var assignee: String?
    @NSManaged var addedBy: String?
    @NSManaged var createdAt: Date?
    @NSManaged var group: SPGroup?

    var title: String { name ?? "" }
    var lineTotal: Double { price * Double(max(quantity, 1)) }
    var imageURL: URL? { image.flatMap(URL.init(string:)) }
}

@objc(SPShelf)
final class SPShelf: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var place: String?
    @NSManaged var order: Int64
    @NSManaged var group: SPGroup?
    @NSManaged var items: NSSet?

    var itemList: [SPPantryItem] {
        (items?.allObjects as? [SPPantryItem] ?? []).sorted { ($0.name ?? "") < ($1.name ?? "") }
    }
}

@objc(SPPantryItem)
final class SPPantryItem: NSManagedObject, Identifiable {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var image: String?
    @NSManaged var productId: String?
    @NSManaged var store: String?
    @NSManaged var price: Double
    @NSManaged var cat: String?
    @NSManaged var quantity: Int64
    @NSManaged var minQuantity: Int64
    @NSManaged var place: String?
    @NSManaged var expiry: Date?
    @NSManaged var createdAt: Date?
    @NSManaged var group: SPGroup?
    @NSManaged var shelf: SPShelf?

    var isMissing: Bool { quantity < max(minQuantity, 1) }
    var imageURL: URL? { image.flatMap(URL.init(string:)) }
}

// MARK: - Contenedor

final class Persistence {
    static let shared = Persistence()
    static let cloudContainerID = "iCloud.com.shoppost.app"

    let container: NSPersistentCloudKitContainer
    private(set) var privateStore: NSPersistentStore?
    private(set) var sharedStore: NSPersistentStore?
    let cloudEnabled: Bool

    var viewContext: NSManagedObjectContext { container.viewContext }

    init() {
        container = NSPersistentCloudKitContainer(name: "ShopPost", managedObjectModel: Self.model)
        let base = NSPersistentContainer.defaultDirectoryURL()
        // Sin cuenta de iCloud (o sin la capacidad en la firma) se guarda solo en el dispositivo.
        cloudEnabled = FileManager.default.ubiquityIdentityToken != nil

        let privateDesc = NSPersistentStoreDescription(url: base.appending(path: "ShopPost.sqlite"))
        let sharedDesc = NSPersistentStoreDescription(url: base.appending(path: "ShopPost-shared.sqlite"))
        for desc in [privateDesc, sharedDesc] {
            desc.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            desc.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }
        if cloudEnabled {
            let p = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.cloudContainerID)
            p.databaseScope = .private
            privateDesc.cloudKitContainerOptions = p
            let s = NSPersistentCloudKitContainerOptions(containerIdentifier: Self.cloudContainerID)
            s.databaseScope = .shared
            sharedDesc.cloudKitContainerOptions = s
            container.persistentStoreDescriptions = [privateDesc, sharedDesc]
        } else {
            container.persistentStoreDescriptions = [privateDesc]
        }

        container.loadPersistentStores { [weak self] desc, error in
            if let error { print("Core Data:", error) }
            guard let self, let url = desc.url else { return }
            let store = self.container.persistentStoreCoordinator.persistentStore(for: url)
            if url.lastPathComponent == "ShopPost-shared.sqlite" { self.sharedStore = store } else { self.privateStore = store }
        }
        #if DEBUG
        // Crea el esquema de CloudKit (entorno de desarrollo) al ejecutar desde Xcode en un iPhone con iCloud.
        // Después hay que desplegarlo a producción en CloudKit Console para TestFlight / App Store.
        if cloudEnabled, ProcessInfo.processInfo.environment["SHOPPOST_INIT_CLOUDKIT_SCHEMA"] == "1" {
            do { try container.initializeCloudKitSchema(options: []) } catch { print("Esquema CloudKit:", error) }
        }
        #endif
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.transactionAuthor = "app"
        try? container.viewContext.setQueryGenerationFrom(.current)
    }

    func save() {
        let ctx = viewContext
        guard ctx.hasChanges else { return }
        do { try ctx.save() } catch { print("Error al guardar:", error) }
    }

    /// Crea un objeto en el mismo almacén (privado o compartido) que el grupo.
    func insert<T: NSManagedObject>(_ type: T.Type, in group: SPGroup?) -> T {
        let obj = T(context: viewContext)
        if let store = group?.objectID.persistentStore ?? privateStore {
            viewContext.assign(obj, to: store)
        }
        return obj
    }

    // MARK: Compartir

    func isShared(_ object: NSManagedObject) -> Bool {
        if object.objectID.persistentStore == sharedStore, sharedStore != nil { return true }
        return existingShare(for: object) != nil
    }

    func isOwner(_ object: NSManagedObject) -> Bool {
        guard object.objectID.persistentStore == sharedStore, sharedStore != nil else { return true }
        return existingShare(for: object)?.currentUserParticipant == existingShare(for: object)?.owner
    }

    func existingShare(for object: NSManagedObject) -> CKShare? {
        guard cloudEnabled else { return nil }
        return (try? container.fetchShares(matching: [object.objectID]))?[object.objectID]
    }

    func canEdit(_ object: NSManagedObject) -> Bool {
        guard cloudEnabled else { return true }
        return container.canUpdateRecord(forManagedObjectWith: object.objectID)
    }

    func participants(of group: SPGroup) -> [CKShare.Participant] {
        existingShare(for: group)?.participants.filter { $0.acceptanceStatus == .accepted || $0.role == .owner } ?? []
    }

    func share(_ group: SPGroup) async throws -> CKShare {
        if let existing = existingShare(for: group) { return existing }
        let (_, share, _) = try await container.share([group], to: nil)
        share[CKShare.SystemFieldKey.title] = "Grupo \(group.title) en Shop Post"
        share.publicPermission = .none
        return share
    }

    func acceptShare(_ metadata: CKShare.Metadata) {
        guard let sharedStore else { return }
        container.acceptShareInvitations(from: [metadata], into: sharedStore) { _, error in
            if let error { print("No se pudo aceptar la invitación:", error) }
        }
    }

    func purge(_ group: SPGroup) {
        if group.objectID.persistentStore == sharedStore, let store = sharedStore, let share = existingShare(for: group),
           share.owner != share.currentUserParticipant {
            // Invitado: salir del grupo compartido.
            container.purgeObjectsAndRecordsInZone(with: share.recordID.zoneID, in: store) { _, _ in }
            return
        }
        viewContext.delete(group)
        save()
    }

    var ckContainer: CKContainer { CKContainer(identifier: Self.cloudContainerID) }

    // MARK: Modelo

    static let model: NSManagedObjectModel = {
        func attr(_ name: String, _ type: NSAttributeType, _ def: Any? = nil) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name = name
            a.attributeType = type
            a.isOptional = true
            if let def { a.defaultValue = def }
            return a
        }
        func entity(_ name: String, _ cls: AnyClass, _ attrs: [NSAttributeDescription]) -> NSEntityDescription {
            let e = NSEntityDescription()
            e.name = name
            e.managedObjectClassName = NSStringFromClass(cls)
            e.properties = attrs
            return e
        }
        func rel(_ name: String, _ dest: NSEntityDescription, toMany: Bool, cascade: Bool = false) -> NSRelationshipDescription {
            let r = NSRelationshipDescription()
            r.name = name
            r.destinationEntity = dest
            r.isOptional = true
            r.minCount = 0
            r.maxCount = toMany ? 0 : 1
            r.deleteRule = cascade ? .cascadeDeleteRule : .nullifyDeleteRule
            return r
        }

        let group = entity("SPGroup", SPGroup.self, [
            attr("id", .UUIDAttributeType), attr("name", .stringAttributeType, "Casa"),
            attr("emoji", .stringAttributeType, "🛒"), attr("createdAt", .dateAttributeType),
        ])
        let item = entity("SPItem", SPItem.self, [
            attr("id", .UUIDAttributeType), attr("productId", .stringAttributeType), attr("store", .stringAttributeType),
            attr("name", .stringAttributeType, ""), attr("brand", .stringAttributeType), attr("image", .stringAttributeType),
            attr("price", .doubleAttributeType, 0.0), attr("size", .stringAttributeType), attr("unit", .stringAttributeType),
            attr("unitPrice", .doubleAttributeType, 0.0), attr("cat", .stringAttributeType, "otros"),
            attr("quantity", .integer64AttributeType, 1), attr("checked", .booleanAttributeType, false),
            attr("checkedBy", .stringAttributeType), attr("note", .stringAttributeType),
            attr("substituteId", .stringAttributeType), attr("substituteName", .stringAttributeType),
            attr("substitutePrice", .doubleAttributeType, 0.0), attr("substituteImage", .stringAttributeType),
            attr("notInStore", .booleanAttributeType, false), attr("assignee", .stringAttributeType),
            attr("addedBy", .stringAttributeType), attr("createdAt", .dateAttributeType),
        ])
        let shelf = entity("SPShelf", SPShelf.self, [
            attr("id", .UUIDAttributeType), attr("name", .stringAttributeType, "Balda"),
            attr("place", .stringAttributeType, "despensa"), attr("order", .integer64AttributeType, 0),
        ])
        let pantry = entity("SPPantryItem", SPPantryItem.self, [
            attr("id", .UUIDAttributeType), attr("name", .stringAttributeType, ""), attr("image", .stringAttributeType),
            attr("productId", .stringAttributeType), attr("store", .stringAttributeType),
            attr("price", .doubleAttributeType, 0.0), attr("cat", .stringAttributeType, "otros"),
            attr("quantity", .integer64AttributeType, 1), attr("minQuantity", .integer64AttributeType, 1),
            attr("place", .stringAttributeType, "despensa"), attr("expiry", .dateAttributeType),
            attr("createdAt", .dateAttributeType),
        ])

        let gItems = rel("items", item, toMany: true, cascade: true), iGroup = rel("group", group, toMany: false)
        gItems.inverseRelationship = iGroup; iGroup.inverseRelationship = gItems
        let gShelves = rel("shelves", shelf, toMany: true, cascade: true), sGroup = rel("group", group, toMany: false)
        gShelves.inverseRelationship = sGroup; sGroup.inverseRelationship = gShelves
        let gPantry = rel("pantry", pantry, toMany: true, cascade: true), pGroup = rel("group", group, toMany: false)
        gPantry.inverseRelationship = pGroup; pGroup.inverseRelationship = gPantry
        let sItems = rel("items", pantry, toMany: true), pShelf = rel("shelf", shelf, toMany: false)
        sItems.inverseRelationship = pShelf; pShelf.inverseRelationship = sItems

        group.properties += [gItems, gShelves, gPantry]
        item.properties += [iGroup]
        shelf.properties += [sGroup, sItems]
        pantry.properties += [pGroup, pShelf]

        let m = NSManagedObjectModel()
        m.entities = [group, item, shelf, pantry]
        return m
    }()
}
