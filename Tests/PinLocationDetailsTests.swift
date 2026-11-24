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
}
