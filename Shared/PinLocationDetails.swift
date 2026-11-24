import Foundation

struct PinLocationDetails {
    struct Candidate {
        let name: String?
        let address: String?
        let distance: Double
    }

    let name: String
    let address: String?

    static func reverseGeocoded(_ candidates: [Candidate]) -> Self? {
        // A reverse-geocoded result can be centered on a nearby feature.
        // Keep street-level addresses tied to the immediate area of the pin.
        let nearby = candidates.filter { (0...75).contains($0.distance) }
            .sorted { $0.distance < $1.distance }
        for candidate in nearby {
            if let address = singleLine(candidate.address) {
                return Self(name: String((singleLine(candidate.name) ?? address).prefix(120)),
                            address: String(address.prefix(300)))
            }
        }
        guard let name = nearby.lazy.compactMap({ singleLine($0.name) }).first else { return nil }
        return Self(name: String(name.prefix(120)), address: nil)
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
