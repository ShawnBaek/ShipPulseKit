import ShipPulseKit
import SwiftUI

enum Route: Hashable { case grid, list }

struct HomeView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Photo Grid", value: Route.grid)
                NavigationLink("Photo List", value: Route.list)
            }
            .navigationTitle("ShipPulseKit Sample")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .grid: PhotoGridView()
                case .list: PhotoListView()
                }
            }
            .shipPulseScreen("Home")
        }
    }
}

struct PhotoGridView: View {
    @Environment(Catalog.self) private var catalog
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 4)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(catalog.photos) { photo in
                    PhotoThumbnail(photo: photo)
                        .aspectRatio(1, contentMode: .fill)
                }
            }
        }
        .navigationTitle("Photo Grid")
        // MetricKit hitch time and ratio for this region, only while scrolling.
        .shipPulseScrollHitches("PhotoGridScroll")
        // Per-screen MetricKit metrics, named after this file.
        .shipPulseScreen()
    }
}

struct PhotoListView: View {
    @Environment(Catalog.self) private var catalog
    @State private var expanded: Set<Photo.ID> = []

    var body: some View {
        List(catalog.photos) { photo in
            HStack(spacing: 12) {
                PhotoThumbnail(photo: photo)
                    .frame(width: expanded.contains(photo.id) ? 120 : 56, height: expanded.contains(photo.id) ? 120 : 56)
                    .clipShape(.rect(cornerRadius: 8))
                Text(photo.title)
            }
            .contentShape(.rect)
            .onTapGesture {
                // Measures hitches for this animation until it completes.
                ShipPulseKit.withAnimation("ExpandRow", .spring) {
                    if expanded.contains(photo.id) { expanded.remove(photo.id) } else { expanded.insert(photo.id) }
                }
            }
        }
        .navigationTitle("Photo List")
        .shipPulseScrollHitches("PhotoListScroll")
        .shipPulseScreen()
    }
}

struct PhotoThumbnail: View {
    let photo: Photo

    var body: some View {
        ZStack {
            LinearGradient(colors: [photo.color, photo.color.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: photo.symbol)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}
