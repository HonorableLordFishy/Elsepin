#if !ELSEPIN_UI_TESTING || !targetEnvironment(simulator)
#error("Validation search adapter must never compile into a device app")
#endif
import MapKit
import Combine

struct PlaceSearchResponse { let mapItems: [MKMapItem] }
@MainActor final class PlaceSearchRequest {
    private let query: String
    private let requiredRegion: MKCoordinateRegion?
    private var cancelled = false
    private var pendingSlowResponse: CheckedContinuation<Void, Never>?
    private static var retryAttempts = 0
    init(_ request: MKLocalSearch.Request) {
        query = request.naturalLanguageQuery ?? ""
        requiredRegion = request.regionPriority == .required ? request.region : nil
    }
    init(pointsOfInterest request: MKLocalPointsOfInterestRequest) {
        query = "poi"
        requiredRegion = nil
    }
    func cancel() {
        cancelled = true
        // Release only after the real view cancels/replaces the request. A timer
        // could finish while XCTest was locating Cancel, moving the target away.
        let pending = pendingSlowResponse
        pendingSlowResponse = nil
        pending?.resume()
    }
    func start(seconds: Double = 7) async throws -> PlaceSearchResponse {
        guard ValidationFixture.enabled else { throw URLError(.unsupportedURL) }
        // 'retry' fails both normal and broader lookup once, then succeeds.
        if query == "retry" {
            Self.retryAttempts += 1
            if Self.retryAttempts <= 2 { throw URLError(.notConnectedToInternet) }
        }
        // Deliberately return a stale response after cancellation. The production
        // view must reject it using its task/generation guards, not fixture timing.
        if query == "slow" {
            await withCheckedContinuation { continuation in
                if cancelled { continuation.resume() }
                else { pendingSlowResponse = continuation }
            }
        } else { try await Task.sleep(for: .milliseconds(150)) }
        if ValidationFixture.scenario == "route-search-coverage", query == "Coffee" {
            return .init(mapItems: corridorResults())
        }
        // Keep search results away from named fixture pins: the real search flow
        // deliberately substitutes a saved name at matching coordinates.
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: 40.772, longitude: -73.973)))
        item.name = query == "slow" ? "OBSOLETE TEST RESULT" : "Test cafe result for \(query)"
        return PlaceSearchResponse(mapItems: [item])
    }

    private func corridorResults() -> [MKMapItem] {
        guard let region = requiredRegion else { return [] }
        let points = ValidationFixture.searchCorridorPoints
        let candidates = [
            ("Start cafe", points[0].latitude + 0.002, points[0].longitude + 0.015),
            ("Start café", points[0].latitude + 0.002, points[0].longitude + 0.015),
            ("Middle cafe", points[1].latitude - 0.008, points[1].longitude),
            ("Destination cafe", points[2].latitude + 0.002, points[2].longitude - 0.015),
            ("Off-route cafe", points[1].latitude + 0.055, points[1].longitude)
        ]
        return candidates.compactMap { name, latitude, longitude in
            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            // A bounded local response represents places near each request's
            // center, including the off-route item within the provider area.
            guard region.containsPlace(coordinate),
                  RoutePoint(region.center).distance(to: RoutePoint(coordinate)) < 7_000 else { return nil }
            let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
            item.name = name
            return item
        }
    }
    static func configure(_ request: MKLocalSearch.Request, query: String) { request.naturalLanguageQuery = query }
    static func message(for error: Error) -> String {
        "You're offline. Reconnect and try again; saved pins still work."
    }
}
extension PlaceSearchIntent {
    var mapCategories: [MKPointOfInterestCategory] { [.restaurant] }
}
@MainActor final class PlaceSearchCompleter: ObservableObject {
    @Published var results: [MKLocalSearchCompletion] = []
    var query = ""
    func setRegion(_ region: MKCoordinateRegion?) {}
}
