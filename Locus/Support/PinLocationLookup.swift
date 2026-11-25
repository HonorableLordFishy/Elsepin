import Contacts
import MapKit

/// Runs only for a selected pin, never movement ticks or map panning. Each
/// request has a deadline and cancellation; callers must reject obsolete results.
@MainActor enum PinLocationLookup {
    static func resolve(_ coordinate: CLLocationCoordinate2D, includeNearbyName: Bool = true) async -> PinLocationDetails? {
        guard CLLocationCoordinate2DIsValid(coordinate), !Task.isCancelled else { return nil }
#if ELSEPIN_UI_TESTING
        if ValidationFixture.scenario == "pin-address-refresh", RoutePoint(coordinate) == RoutePoint(ValidationFixture.points[0]) {
            return PinLocationDetails(name: "Geocoder name", address: ValidationFixture.updatedPinAddress)
        }
        if ValidationFixture.scenario == "home-solid-pin-layout" {
            let address = RoutePoint(coordinate) == RoutePoint(ValidationFixture.points[0])
                ? ValidationFixture.shortPinLayoutAddress : ValidationFixture.longPinLayoutAddress
            return PinLocationDetails(name: "Dropped pin", address: address)
        }
#endif
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        var candidates: [PinLocationDetails.Candidate] = []
        if #available(iOS 26.0, *) {
            if let request = MKReverseGeocodingRequest(location: location) {
                let timeout = Task { @MainActor in
                    do { try await Task.sleep(for: .seconds(5)) } catch { return }
                    request.cancel()
                }
                defer { timeout.cancel() }
                let items = try? await withTaskCancellationHandler {
                    try await request.mapItems
                } onCancel: { Task { @MainActor in request.cancel() } }
                candidates = (items ?? []).map { item in
                    let address = PinLocationDetails.singleLine(item.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true))
                        ?? PinLocationDetails.singleLine(item.address?.fullAddress)
                        ?? item.address?.shortAddress
                    return .init(name: item.name, address: address, distance: item.location.distance(from: location),
                                 context: item.addressRepresentations?.cityWithContext)
                }
            }
        } else {
            let geocoder = CLGeocoder()
            let timeout = Task { @MainActor in
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                geocoder.cancelGeocode()
            }
            defer { timeout.cancel() }
            let marks = try? await withTaskCancellationHandler {
                try await geocoder.reverseGeocodeLocation(location)
            } onCancel: { Task { @MainActor in geocoder.cancelGeocode() } }
            candidates = (marks ?? []).map { mark in
                let street = [mark.subThoroughfare, mark.thoroughfare].compactMap { $0 }.joined(separator: " ")
                let fallback = [street, mark.locality, mark.administrativeArea, mark.postalCode]
                    .compactMap { PinLocationDetails.singleLine($0) }.joined(separator: ", ")
                let postalAddress = mark.postalAddress.map { CNPostalAddressFormatter.string(from: $0, style: .mailingAddress) }
                let context = [mark.thoroughfare, mark.locality, mark.administrativeArea]
                    .compactMap { PinLocationDetails.singleLine($0) }.joined(separator: ", ")
                return .init(name: mark.name, address: PinLocationDetails.singleLine(postalAddress) ?? fallback,
                             distance: mark.location?.distance(from: location) ?? .infinity, context: context)
            }
        }
        guard !Task.isCancelled else { return nil }
        if let details = PinLocationDetails.reverseGeocoded(candidates) { return details }
        // A point of interest is only a fallback label. The coordinate and any
        // available postal address remain independent of nearby businesses.
        if includeNearbyName {
            let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: PinLocationDetails.nearbySearchRadiusMetres)
            let nearby = PlaceSearchRequest(pointsOfInterest: request)
            if let response = try? await nearby.start(seconds: 3), !Task.isCancelled {
                let landmarks = response.mapItems.map {
                    PinLocationDetails.Candidate(name: $0.name, address: nil, distance: distance($0, from: location))
                }
                if let details = PinLocationDetails.nearLandmark(landmarks) { return details }
            }
        }
        guard !Task.isCancelled else { return nil }
        return PinLocationDetails.reverseGeocodedContext(candidates) ?? PinLocationDetails(name: "Dropped pin", address: nil)
    }

    private static func distance(_ item: MKMapItem, from location: CLLocation) -> CLLocationDistance {
        if #available(iOS 26.0, *) { return item.location.distance(from: location) }
        return item.placemark.location?.distance(from: location) ?? .infinity
    }
}
