import Foundation

struct PinLocationDetails {
    static let nearbySearchRadiusMetres: Double = 30
    private static let nearbyNameMetres: Double = 15
    private static let nearbyNameLeadMetres: Double = 8
    private static let reverseGeocodedMatchMetres: Double = 10
    private static let reverseGeocodedContextMetres: Double = 25

    struct Candidate {
        let name: String?
        let address: String?
        let distance: Double
        let context: String?

        init(name: String?, address: String?, distance: Double, context: String? = nil) {
            self.name = name
            self.address = address
            self.distance = distance
            self.context = context
        }
    }

    let name: String
    let address: String?

    static func reverseGeocoded(_ candidates: [Candidate]) -> Self? {
        // A reverse-geocoded result can be centered on a nearby feature.
        // Keep specific addresses and names tied to the immediate area of the pin.
        let nearby = candidates.filter { (0...reverseGeocodedMatchMetres).contains($0.distance) }
            .sorted { $0.distance < $1.distance }
        for candidate in nearby {
            if let address = singleLine(candidate.address) {
                let name = singleLine(candidate.name) ?? address
                return Self(name: String(name.prefix(120)),
                            address: String(address.prefix(300)))
            }
        }
        guard let name = nearby.lazy.compactMap({ singleLine($0.name) }).first else { return nil }
        return Self(name: String(name.prefix(120)), address: nil)
    }

    static func reverseGeocodedContext(_ candidates: [Candidate]) -> Self? {
        let nearby = candidates.filter { (0...reverseGeocodedContextMetres).contains($0.distance) }
            .sorted { $0.distance < $1.distance }
        guard let context = nearby.lazy.compactMap({ singleLine($0.context) }).first else { return nil }
        return Self(name: String(context.prefix(120)), address: nil)
    }

    static func nearLandmark(_ candidates: [Candidate]) -> Self? {
        let landmarks = candidates.compactMap { candidate -> (name: String, distance: Double)? in
            guard (0...nearbySearchRadiusMetres).contains(candidate.distance),
                  let name = singleLine(candidate.name) else { return nil }
            return (name, candidate.distance)
        }.sorted { $0.distance < $1.distance }
        guard let closest = landmarks.first, closest.distance <= nearbyNameMetres else { return nil }
        let competingLandmark = landmarks.dropFirst().first {
            $0.name.localizedCaseInsensitiveCompare(closest.name) != .orderedSame
        }
        if let competingLandmark, competingLandmark.distance - closest.distance < nearbyNameLeadMetres { return nil }
        return Self(name: String("Near \(closest.name)".prefix(120)), address: nil)
    }

    static func singleLine(_ value: String?) -> String? {
        guard let value else { return nil }
        let line = value.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        return line.isEmpty ? nil : line
    }
}
