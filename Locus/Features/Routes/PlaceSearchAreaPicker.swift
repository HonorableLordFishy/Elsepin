import MapKit
import SwiftUI

/// Choosing a search viewport never edits an endpoint or starts movement.
struct PlaceSearchAreaPicker: View {
    let route: PlannedRoute?
    let onChoose: (MKCoordinateRegion) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition
    @State private var region: MKCoordinateRegion

    init(initialRegion: MKCoordinateRegion, route: PlannedRoute? = nil, fitRouteInitially: Bool = true,
         onChoose: @escaping (MKCoordinateRegion) -> Void) {
        self.route = route
        self.onChoose = onChoose
        if fitRouteInitially, let route, route.coordinates.count > 1 {
            let rect = MKPolyline(coordinates: route.coordinates, count: route.coordinates.count).boundingMapRect
            let paddedRect = rect.insetBy(dx: -max(rect.size.width * 0.15, 500),
                                          dy: -max(rect.size.height * 0.15, 500))
            _position = State(initialValue: .rect(paddedRect))
            _region = State(initialValue: MKCoordinateRegion(paddedRect))
        } else {
            _position = State(initialValue: .region(initialRegion))
            _region = State(initialValue: initialRegion)
        }
    }

    var body: some View {
        NavigationStack {
            Map(position: $position, interactionModes: [.pan, .zoom]) {
                if let route {
                    MapPolyline(coordinates: route.coordinates).stroke(LocusTheme.accent, lineWidth: 4)
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .onMapCameraChange(frequency: .onEnd) { context in
                if context.region.searchBounds.isValid { region = context.region }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                MapLocationSearch(center: nil) { coordinate in
                    let selected = MKCoordinateRegion(center: coordinate, latitudinalMeters: 12_000, longitudinalMeters: 12_000)
                    region = selected; position = .region(selected)
                }.padding(12).background(ShiftCanvas())
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    Text("Find a city, then move or zoom to the area you want.").font(.caption).foregroundStyle(.secondary)
                    Button("Use this area") { onChoose(region); dismiss() }
                        .buttonStyle(ShiftActionStyle(compact: true)).disabled(!region.searchBounds.isValid)
                }.padding(12).background(ShiftCanvas())
            }
            .navigationTitle("Search area").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
