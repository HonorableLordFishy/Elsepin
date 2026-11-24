import XCTest
@testable import SessionPresentation

final class HeldLocationSymbolTests: XCTestCase {
    func testAutomaticSymbolFollowsModeAndExplicitChoiceDoesNot() {
        XCTAssertEqual(HeldLocationSymbol.automatic.icon(travelMode: .walk), TravelMode.walk.icon)
        XCTAssertEqual(HeldLocationSymbol.automatic.icon(travelMode: .drive), TravelMode.drive.icon)
        for mode in TravelMode.allCases {
            XCTAssertEqual(HeldLocationSymbol.star.icon(travelMode: mode), "star.fill")
        }
    }

    func testStoredSymbolUsesItsDefaultsSuiteAndResetsWithSettings() throws {
        let personalName = UUID().uuidString
        let demoName = UUID().uuidString
        let personal = try XCTUnwrap(UserDefaults(suiteName: personalName))
        let demo = try XCTUnwrap(UserDefaults(suiteName: demoName))
        defer {
            personal.removePersistentDomain(forName: personalName)
            demo.removePersistentDomain(forName: demoName)
        }

        XCTAssertEqual(HeldLocationSymbol.stored(in: personal), .automatic)
        personal.set(HeldLocationSymbol.person.rawValue, forKey: HeldLocationSymbol.preferenceKey)
        demo.set("invalid", forKey: HeldLocationSymbol.preferenceKey)
        XCTAssertEqual(HeldLocationSymbol.stored(in: personal), .person)
        XCTAssertEqual(HeldLocationSymbol.stored(in: demo), .automatic)

        AppResetRules.clearPreferences(in: personal, scope: .settings)
        XCTAssertNil(personal.object(forKey: HeldLocationSymbol.preferenceKey))
        XCTAssertEqual(HeldLocationSymbol.stored(in: personal), .automatic)
    }
}
