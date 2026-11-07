import BackgroundTasks
import CloudKit
import SwiftUI
import UIKit

@main
struct ShopPostApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(ShopModel.shared)
                .environment(CatalogService.shared)
                .environment(Preferences.shared)
                .environment(\.managedObjectContext, Persistence.shared.viewContext)
                .tint(Color.spInk)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { AppDelegate.scheduleRefresh() }
            if phase == .active { Task { await CatalogService.shared.refresh() } }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    static let refreshTask = "com.shoppost.app.refresh"

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 400 << 20)
        application.registerForRemoteNotifications()
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTask, using: nil) { task in
            Self.scheduleRefresh()
            let work = Task { @MainActor in
                await CatalogService.shared.refresh()
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
        return true
    }

    static func scheduleRefresh() {
        let req = BGAppRefreshTaskRequest(identifier: refreshTask)
        req.earliestBeginDate = Date().addingTimeInterval(6 * 3600)
        try? BGTaskScheduler.shared.submit(req)
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

/// Recibe las invitaciones a grupos compartidos (CKShare).
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Persistence.shared.acceptShare(metadata)
        Task { @MainActor in ShopModel.shared.show("Te has unido a «\(metadata.share[CKShare.SystemFieldKey.title] as? String ?? "un grupo")»") }
    }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            Persistence.shared.acceptShare(metadata)
        }
    }
}
