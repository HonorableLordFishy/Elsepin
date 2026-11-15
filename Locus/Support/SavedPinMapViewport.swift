import MapKit

/// Camera samples are deliberately not observable. Map motion must not invalidate
/// the whole screen every frame; views publish only a changed set of saved pins.
@MainActor final class SavedPinMapViewport {
    private(set) var rect: MKMapRect?
    private(set) var widthMeters: Double?
    private var cadence = SavedPinRefreshCadence()

    func update(rect: MKMapRect, size: CGSize, project: (CGPoint) -> CLLocationCoordinate2D?) {
        self.rect = rect
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return }
        // A short sample avoids shortest-path wrapping at the date line and
        // world zoom levels. Pitch is disabled on both of these map surfaces.
        let halfSample = min(16, size.width / 4)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        guard let left = project(CGPoint(x: center.x - halfSample, y: center.y)),
              let right = project(CGPoint(x: center.x + halfSample, y: center.y)),
              CLLocationCoordinate2DIsValid(left), CLLocationCoordinate2DIsValid(right) else {
            widthMeters = nil
            return
        }
        let distance = CLLocation(latitude: left.latitude, longitude: left.longitude)
            .distance(from: CLLocation(latitude: right.latitude, longitude: right.longitude))
        widthMeters = SavedPinVisibility.mapWidthMeters(sampleMeters: distance,
            samplePoints: halfSample * 2, viewportPoints: size.width)
    }

    func isVisible(maximumMiles: Double) -> Bool {
        SavedPinVisibility.isVisible(mapWidthMeters: widthMeters, maximumMiles: maximumMiles)
    }

    func shouldRefresh(maximumMiles: Double, enabled: Bool = true, force: Bool = false) -> Bool {
        cadence.shouldRefresh(visible: enabled && isVisible(maximumMiles: maximumMiles),
            now: ProcessInfo.processInfo.systemUptime, force: force)
    }

    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        rect?.contains(MKMapPoint(coordinate)) ?? false
    }
}
