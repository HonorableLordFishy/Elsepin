import Foundation

/// Search regions are hints to the provider. Filter actual returned coordinates
/// against the path; proximity is never presented as a driving/cycling detour.
struct RouteSearchCorridor {
    private static let maxRegions = 11
    private static let maxDiameter = 200_000.0

    struct Region {
        let center: RoutePoint
        let diameter: Double
    }
    struct Match: Equatable {
        let metresAlong: Double
        let metresAway: Double
    }
    let track: RouteTrack
    let index: RouteSnapIndex
    let width: Double

    /// `width` is the corridor half-width in metres. The default is deliberately
    /// generous so along-route category searches are not sparse; callers can narrow it.
    init(track: RouteTrack, width: Double = 5_000) {
        self.track = track
        index = RouteSnapIndex(track: track)
        self.width = width.isFinite ? max(100, min(20_000, width)) : 5_000
    }

    private var maxSpan: Double { Self.maxDiameter - width * 2 }
    private var regionCount: Int {
        let desired = Int(ceil(min(track.length / 20_000, Double(Self.maxRegions))))
        // A single local window is enough for short routes. Once the path
        // needs multiple windows, give its middle a request of its own.
        return desired <= 1 ? 1 : max(3, desired)
    }
    var samplesLongRoute: Bool { track.length > maxSpan * Double(Self.maxRegions) }

    var regions: [Region] {
        let count = regionCount
        let span = track.length / Double(count)
        if samplesLongRoute {
            // Move the outside centres inward by half a usable window so each
            // endpoint still has corridor padding and little coverage is wasted.
            let step = (track.length - maxSpan) / Double(count - 1)
            return (0..<count).map { index in
                Region(center: track.point(at: maxSpan / 2 + Double(index) * step), diameter: Self.maxDiameter)
            }
        }
        return (0..<count).map { bucket in
            Region(center: track.point(at: (Double(bucket) + 0.5) * span),
                   diameter: span + width * 2)
        }
    }

    /// Search both ends and the middle first, so a deadline or cancellation
    /// still gives widely spaced sections a chance to return results.
    var prioritizedRegions: [Region] {
        let windows = regions
        var order = [windows.startIndex]
        var remaining = Array(windows.indices.dropFirst())
        while !remaining.isEmpty {
            let next = remaining.indices.max { left, right in
                let leftGap = order.map { abs(remaining[left] - $0) }.min() ?? 0
                let rightGap = order.map { abs(remaining[right] - $0) }.min() ?? 0
                return leftGap < rightGap
            } ?? remaining.startIndex
            order.append(remaining.remove(at: next))
        }
        return order.map { windows[$0] }
    }

    /// Prefer nearby places within each section. Take turns between populated
    /// sections before sorting the selected results in itinerary order.
    func representativeIndices(for matches: [Match], limit: Int = 30) -> [Int] {
        guard limit > 0 else { return [] }
        // Result diversity is independent of the provider request count. One
        // dense pocket of results can otherwise fill a short route's list.
        let sectionCount = min(max(3, regionCount), limit)
        var sections = Array(repeating: [Int](), count: sectionCount)
        let ranked = matches.indices.sorted {
            let left = matches[$0].metresAway, right = matches[$1].metresAway
            return left == right ? $0 < $1 : left < right
        }
        for index in ranked {
            let fraction = min(1, max(0, matches[index].metresAlong / track.length))
            let section = min(sectionCount - 1, Int(fraction * Double(sectionCount)))
            sections[section].append(index)
        }

        var selected: [Int] = []
        let rounds = min(limit, sections.map(\.count).max() ?? 0)
        for round in 0..<rounds {
            for section in sections where section.indices.contains(round) && selected.count < limit {
                selected.append(section[round])
            }
        }
        return selected.sorted {
            let left = matches[$0].metresAlong, right = matches[$1].metresAlong
            return left == right ? $0 < $1 : left < right
        }
    }

    func match(_ point: RoutePoint) -> Match? {
        guard let nearest = index.nearest(to: point) else { return nil }
        let distance = track.point(at: nearest.metres).distance(to: point)
        guard distance <= width else { return nil }
        return Match(metresAlong: nearest.metres, metresAway: distance)
    }

    /// Insert into the current itinerary without changing the order of existing
    /// stops (including loop routes). Unmatched places retain append behavior.
    func insertionIndex(for point: RoutePoint, stopMetres: [Double]) -> Int {
        guard let match = match(point) else { return stopMetres.count }
        return stopMetres.firstIndex { $0 > match.metresAlong + 1 } ?? stopMetres.count
    }

    static func isDuplicate(name: String, point: RoutePoint, ofName otherName: String, point other: RoutePoint) -> Bool {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) ==
            otherName.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) &&
            point.isValid && other.isValid && point.distance(to: other) <= 40
    }
}
