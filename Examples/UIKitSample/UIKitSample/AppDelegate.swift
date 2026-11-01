import ShipPulseKit
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // The only required line. In UIKit, every view controller is also tracked as a screen.
        do {
            try ShipPulseKit.start()
        } catch {
            print("ShipPulseKit: \(error.localizedDescription)")
        }
        return true
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UINavigationController(rootViewController: HomeViewController())
        window.makeKeyAndVisible()
        self.window = window

        // Launch work counted in MetricKit's extended launch time.
        Task { @MainActor in
            await ShipPulseKit.trackLaunchTask("LoadCatalog") { await Catalog.shared.load() }
        }
    }
}

@MainActor
final class Catalog {
    static let shared = Catalog()
    private(set) var photos: [Photo] = []

    func load() async {
        photos = await Photo.makeCatalog(count: 300)
        NotificationCenter.default.post(name: .catalogDidLoad, object: nil)
    }
}

extension Notification.Name {
    static let catalogDidLoad = Notification.Name("catalogDidLoad")
}
