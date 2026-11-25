import XCTest
@testable import SessionPresentation

final class PinLocationDetailsTests: XCTestCase {
    func testClosestAddressBeatsNameOnlyAndUnsortedReverseGeocoderResults() {
        let details = PinLocationDetails.reverseGeocoded([
            .init(name: "Different building", address: "80 Main Street", distance: 40),
            .init(name: "Neighborhood", address: " ", distance: 1),
            .init(name: "Library", address: "12 Main Street\r\n\n Portland, OR 97201", distance: 8)
        ])

        XCTAssertEqual(details?.name, "Library")
        XCTAssertEqual(details?.address, "12 Main Street, Portland, OR 97201")
    }

    func testDistantOrUnlocatedAddressesDoNotBecomePinAddresses() {
        let details = PinLocationDetails.reverseGeocoded([
            .init(name: "Distant building", address: "80 Main Street", distance: 200),
            .init(name: "Unlocated building", address: "20 Main Street", distance: .infinity),
            .init(name: "Park", address: nil, distance: 0)
        ])

        XCTAssertEqual(details?.name, "Park")
        XCTAssertNil(details?.address)
    }

    func testMissingNameUsesTheAddressWithoutMovingThePin() {
        let details = PinLocationDetails.reverseGeocoded([
            .init(name: "  ", address: "  12 Main Street  ", distance: 0)
        ])

        XCTAssertEqual(details?.name, "12 Main Street")
        XCTAssertEqual(details?.address, "12 Main Street")
    }

    func testReverseGeocoderRejectsSeparateBuildingAndKeepsStreetContext() {
        let candidates = [
            PinLocationDetails.Candidate(name: "Sand Breeze Cottage", address: "80 Main Street",
                                         distance: 18, context: "Main Street, Portland")
        ]

        XCTAssertNil(PinLocationDetails.reverseGeocoded(candidates))
        XCTAssertEqual(PinLocationDetails.reverseGeocodedContext(candidates)?.name, "Main Street, Portland")
        XCTAssertNil(PinLocationDetails.reverseGeocodedContext(candidates)?.address)
        XCTAssertNil(PinLocationDetails.reverseGeocoded([
            .init(name: "Sand Breeze Cottage", address: "80 Main Street", distance: 40)
        ]))
    }

    func testNearbyLandmarkRequiresAConfidentDistanceLead() {
        let cottage = PinLocationDetails.Candidate(name: "Sand Breeze Cottage", address: nil, distance: 12)
        let nearby = PinLocationDetails.nearLandmark([
            .init(name: "Park", address: nil, distance: 24),
            cottage
        ])

        XCTAssertEqual(nearby?.name, "Near Sand Breeze Cottage")
        XCTAssertNil(nearby?.address)
        XCTAssertNil(PinLocationDetails.nearLandmark([
            cottage,
            .init(name: "Park", address: nil, distance: 15)
        ]))
        XCTAssertNil(PinLocationDetails.nearLandmark([
            .init(name: "Sand Breeze Cottage", address: nil, distance: 30)
        ]))
    }
}
