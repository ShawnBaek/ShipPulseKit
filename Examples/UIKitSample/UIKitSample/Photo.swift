import UIKit

struct Photo: Sendable {
    let id: Int
    let title: String
    let hue: CGFloat
    let symbol: String

    private static let symbols = ["mountain.2.fill", "leaf.fill", "sun.max.fill", "cloud.fill", "camera.fill", "star.fill", "flame.fill", "drop.fill"]

    /// Simulates loading a catalog at launch.
    static func makeCatalog(count: Int) async -> [Photo] {
        try? await Task.sleep(for: .milliseconds(400))
        return (0..<count).map { i in
            Photo(id: i, title: "Photo \(i + 1)", hue: CGFloat(i % 36) / 36, symbol: symbols[i % symbols.count])
        }
    }

    /// Draws a gradient thumbnail with a symbol, rendered on demand like a real image would be.
    func image(size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            let top = UIColor(hue: hue, saturation: 0.6, brightness: 0.85, alpha: 1)
            let bottom = top.withAlphaComponent(0.5)
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
            let config = UIImage.SymbolConfiguration(pointSize: size.width * 0.3, weight: .semibold)
            if let symbol = UIImage(systemName: symbol, withConfiguration: config)?.withTintColor(.white, renderingMode: .alwaysOriginal) {
                symbol.draw(at: CGPoint(x: (size.width - symbol.size.width) / 2, y: (size.height - symbol.size.height) / 2))
            }
        }
    }
}
