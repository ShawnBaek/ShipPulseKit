import SwiftUI

struct Photo: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let hue: Double
    let symbol: String

    var color: Color { Color(hue: hue, saturation: 0.6, brightness: 0.85) }

    private static let symbols = ["mountain.2.fill", "leaf.fill", "sun.max.fill", "cloud.fill", "camera.fill", "star.fill", "flame.fill", "drop.fill"]

    /// Simulates loading a catalog at launch.
    static func makeCatalog(count: Int) async -> [Photo] {
        try? await Task.sleep(for: .milliseconds(400))
        return (0..<count).map { i in
            Photo(id: i, title: "Photo \(i + 1)", hue: Double(i % 36) / 36, symbol: symbols[i % symbols.count])
        }
    }
}
