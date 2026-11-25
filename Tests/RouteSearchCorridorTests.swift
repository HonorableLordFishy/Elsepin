import XCTest
@testable import SessionPresentation

final class RouteSearchCorridorTests: XCTestCase {
    func testBentRouteFiltersByPathRatherThanItsBoundingBox() throws {
        let track = try XCTUnwrap(RouteTrack([
            RoutePoint(latitude: 33.7, longitude: -117.9),
            RoutePoint(latitude: 33.8, longitude: -117.9),
            RoutePoint(latitude: 33.8, longitude: -117.7)
        ]))
        let corridor = RouteSearchCorridor(track: track, width: 500)
        XCTAssertNotNil(corridor.match(RoutePoint(latitude: 33.801, longitude: -117.8)))
        XCTAssertNil(corridor.match(RoutePoint(latitude: 33.71, longitude: -117.71)))
        XCTAssertNil(corridor.match(RoutePoint(latitude: .nan, longitude: 0)))
    }

    func testSearchRegionsAreBoundedAndCoverShortAndLongPaths() throws {
        for end in [0.001, 0.2, 2.0, 9.0, 18.0] {
            let track = try XCTUnwrap(RouteTrack([RoutePoint(latitude: 0, longitude: 0), RoutePoint(latitude: 0, longitude: end)]))
            let corridor = RouteSearchCorridor(track: track)
            XCTAssertFalse(corridor.samplesLongRoute)
            XCTAssertTrue((1...11).contains(corridor.regions.count))
            XCTAssertTrue(corridor.regions.allSatisfy { $0.center.isValid && $0.diameter > 0 && $0.diameter <= 200_000 })
            for step in 0...100 {
                let point = track.point(at: track.length * Double(step) / 100)
                XCTAssertTrue(corridor.regions.contains { $0.center.distance(to: point) <= $0.diameter / 2 })
            }
        }
    }

    func testVeryLongRouteUsesSafeSizedSamplingRegions() throws {
        let track = try XCTUnwrap(RouteTrack([RoutePoint(latitude: 0, longitude: 0), RoutePoint(latitude: 0, longitude: 42)]))
        let corridor = RouteSearchCorridor(track: track)
        XCTAssertTrue(corridor.samplesLongRoute)
        XCTAssertEqual(corridor.regions.count, 11)
        XCTAssertTrue(corridor.regions.allSatisfy { $0.diameter <= 200_000 })
        for (window, fraction) in zip(corridor.prioritizedRegions, [0.0, 1.0, 0.5]) {
            let point = track.point(at: track.length * fraction)
            XCTAssertLessThanOrEqual(window.center.distance(to: point), window.diameter / 2 - corridor.width + 1)
        }
        XCTAssertGreaterThan(corridor.regions[0].center.distance(to: corridor.regions[1].center), 200_000,
                             "Very long routes must be represented honestly as sampled, not exhaustive coverage")
    }

    func testMediumRouteGetsSeparateStartMiddleAndEndSearchWindows() throws {
        let track = try XCTUnwrap(RouteTrack([
            RoutePoint(latitude: 0, longitude: 0),
            RoutePoint(latitude: 0, longitude: 0.29)
        ]))
        let corridor = RouteSearchCorridor(track: track)
        XCTAssertEqual(corridor.prioritizedRegions.count, 3)
        for (window, fraction) in zip(corridor.prioritizedRegions, [1.0 / 6, 5.0 / 6, 0.5]) {
            XCTAssertLessThan(window.center.distance(to: track.point(at: track.length * fraction)), 1)
        }
        for fraction in [0.0, 0.5, 1.0] {
            let point = track.point(at: track.length * fraction)
            XCTAssertTrue(corridor.regions.contains {
                $0.center.distance(to: point) <= $0.diameter / 2 - corridor.width + 1
            })
        }
    }

    func testShortRouteKeepsStartMiddleAndEndMatchesWithOneSearchWindow() throws {
        let track = try XCTUnwrap(RouteTrack([
            RoutePoint(latitude: 0, longitude: 0),
            RoutePoint(latitude: 0, longitude: 0.1)
        ]))
        let corridor = RouteSearchCorridor(track: track)
        XCTAssertEqual(corridor.regions.count, 1)
        var matches = (0..<35).map { RouteSearchCorridor.Match(metresAlong: Double($0) * 50, metresAway: 100) }
        let middle = matches.count
        matches.append(.init(metresAlong: track.length / 2, metresAway: 400))
        let end = matches.count
        matches.append(.init(metresAlong: track.length - 100, metresAway: 600))

        XCTAssertEqual(corridor.representativeIndices(for: matches, limit: 3), [0, middle, end])
        XCTAssertEqual(Array(corridor.representativeIndices(for: matches).suffix(2)), [middle, end])
    }

    func testDenseStartCannotDisplaceMatchesFromLaterInTheRoute() throws {
        let track = try XCTUnwrap(RouteTrack([RoutePoint(latitude: 0, longitude: 0), RoutePoint(latitude: 0, longitude: 9)]))
        let corridor = RouteSearchCorridor(track: track)
        var matches = (0..<40).map { RouteSearchCorridor.Match(metresAlong: Double($0) * 1_000, metresAway: 100) }
        let closerStart = matches.count
        matches.append(.init(metresAlong: 12_000, metresAway: 40))
        let middle = matches.count
        matches.append(.init(metresAlong: track.length / 2, metresAway: 2_000))
        let destination = matches.count
        matches.append(.init(metresAlong: track.length, metresAway: 3_000))

        XCTAssertEqual(Set(corridor.representativeIndices(for: matches, limit: 3)), [closerStart, middle, destination])
        let indices = corridor.representativeIndices(for: matches)
        XCTAssertEqual(indices.count, 30)
        XCTAssertTrue(indices.contains(middle))
        XCTAssertEqual(indices.last, destination)
        let positions = indices.map { matches[$0].metresAlong }
        XCTAssertEqual(positions, positions.sorted())
    }

    func testDateLineResultsAndInsertionKeepExistingStopOrder() throws {
        let track = try XCTUnwrap(RouteTrack([RoutePoint(latitude: 0, longitude: 179.9), RoutePoint(latitude: 0, longitude: -179.9)]))
        let corridor = RouteSearchCorridor(track: track)
        let middle = track.point(at: track.length / 2)
        XCTAssertEqual(try XCTUnwrap(corridor.match(middle)).metresAlong, track.length / 2, accuracy: 1)
        XCTAssertEqual(corridor.insertionIndex(for: middle, stopMetres: [track.length * 0.2, track.length * 0.8]), 1)
        XCTAssertEqual(corridor.insertionIndex(for: RoutePoint(latitude: 5, longitude: 0), stopMetres: [100, 200]), 2)
    }

    func testDuplicateRuleRetainsDifferentNearbyBusinessesAndSeparateBranches() {
        let point = RoutePoint(latitude: 33.7, longitude: -117.8)
        XCTAssertTrue(RouteSearchCorridor.isDuplicate(name: "Café", point: point, ofName: "CAFE", point: point))
        XCTAssertFalse(RouteSearchCorridor.isDuplicate(name: "Cafe", point: point, ofName: "Grocery", point: point))
        XCTAssertFalse(RouteSearchCorridor.isDuplicate(name: "Cafe", point: point, ofName: "Cafe", point: RoutePoint(latitude: 33.72, longitude: -117.8)))
    }

}
