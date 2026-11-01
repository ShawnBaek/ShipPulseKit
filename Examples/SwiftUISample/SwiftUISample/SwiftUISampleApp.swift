import ShipPulseKit
import SwiftUI

@main
struct SwiftUISampleApp: App {
    @State private var catalog = Catalog()

    init() {
        // The only required line. Collects every MetricKit metric, diagnostics and retention.
        do {
            try ShipPulseKit.start()
        } catch {
            print("ShipPulseKit: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(catalog)
                // Launch work counted in MetricKit's extended launch time.
                .task { await ShipPulseKit.trackLaunchTask("LoadCatalog") { await catalog.load() } }
        }
    }
}

@MainActor @Observable
final class Catalog {
    private(set) var photos: [Photo] = []

    func load() async {
        photos = await Photo.makeCatalog(count: 300)
    }
}
