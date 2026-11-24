import XCTest
@testable import SessionPresentation

final class RecoverableJSONListTests: XCTestCase {
    private struct Record: Codable, Equatable {
        let id: Int
        let name: String
    }

    private final class InMemoryStore: PersistedDataStore {
        var values: [String: Any] = [:]
        func data(forKey defaultName: String) -> Data? { values[defaultName] as? Data }
        func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
        func removeObject(forKey defaultName: String) { values.removeValue(forKey: defaultName) }
    }

    private func loaded(_ result: RecoverableJSONList<Record>.LoadResult) -> [Record]? {
        guard case .loaded(let values) = result else { return nil }
        return values
    }

    func testMissingValidAndEmptyDataAreDistinct() throws {
        let store = InMemoryStore()
        let list = RecoverableJSONList<Record>(key: "list", store: store)
        if case .missing = list.load() {} else { XCTFail("Expected missing") }
        XCTAssertFalse(list.hasRecovery)

        let values = [Record(id: 1, name: "One")]
        XCTAssertTrue(list.save(values))
        XCTAssertEqual(loaded(list.load()), values)
        XCTAssertFalse(list.hasRecovery)

        store.set(Data(), forKey: "list")
        if case .unreadable = list.load() {} else { XCTFail("Expected unreadable") }
        XCTAssertTrue(list.hasRecovery, "Even a zero-byte corrupt original should be visible")
    }

    func testUnreadableOriginalIsPreservedOnceAndNotReplaced() throws {
        let store = InMemoryStore()
        let list = RecoverableJSONList<Record>(key: "list", store: store)
        let first = Data("first unreadable original".utf8)
        store.set(first, forKey: "list")
        if case .unreadable = list.load() {} else { XCTFail("Expected unreadable") }
        XCTAssertEqual(store.values["list.recovery"] as? Data, first)

        let second = Data("a later unreadable value".utf8)
        store.set(second, forKey: "list")
        if case .unreadable = list.load() {} else { XCTFail("Expected unreadable") }
        XCTAssertEqual(store.values["list.recovery"] as? Data, first,
                       "A later failure must not replace the only recovery copy")
    }

    func testSavingNewDataKeepsRecoveryCopy() throws {
        let store = InMemoryStore()
        let list = RecoverableJSONList<Record>(key: "list", store: store)
        let original = Data("not json".utf8)
        store.set(original, forKey: "list")
        _ = list.load()
        let values = [Record(id: 2, name: "Two")]
        XCTAssertTrue(list.save(values))
        XCTAssertEqual(loaded(list.load()), values)
        XCTAssertEqual(store.values["list.recovery"] as? Data, original)
    }

    func testRestoreWritesLiveDataAndRemovesRecovery() throws {
        let store = InMemoryStore()
        let list = RecoverableJSONList<Record>(key: "list", store: store)
        let values = [Record(id: 3, name: "Three")]
        store.set(try JSONEncoder().encode(values), forKey: "list.recovery")
        XCTAssertEqual(list.recovery(), values)
        XCTAssertEqual(list.restoreRecovery(), values)
        XCTAssertEqual(loaded(list.load()), values)
        XCTAssertFalse(list.hasRecovery)
    }

    func testPreviewUsesRestoreValidationAndRestoresSameBytesAfterReordering() throws {
        let store = InMemoryStore()
        let list = RecoverableJSONList<Record>(key: "list", store: store)
        let rejected = try JSONEncoder().encode([Record(id: 0, name: "Rejected")])
        let previewed = [Record(id: 1, name: "Previewed")]
        let previewedBytes = try JSONEncoder().encode(previewed)
        let other = try JSONEncoder().encode([Record(id: 2, name: "Other")])
        store.set(rejected, forKey: "list.recovery")
        store.set(try JSONEncoder().encode([previewedBytes, other]), forKey: "list.recovery.history")
        let copy = try XCTUnwrap(list.recoveryCopy { $0.first?.id == 0 ? nil : $0 })
        XCTAssertEqual(copy.values, previewed)

        store.set(other, forKey: "list.recovery")
        store.set(try JSONEncoder().encode([rejected, previewedBytes]), forKey: "list.recovery.history")
        XCTAssertEqual(list.restoreRecovery(copy), previewed)
        XCTAssertEqual(loaded(list.load()), previewed)
        XCTAssertEqual(list.recoveryCopies, [other, rejected])
    }

    func testRemovedPreviewDoesNotRestoreAnotherCopyOrConsumeOriginals() throws {
        let store = InMemoryStore()
        let list = RecoverableJSONList<Record>(key: "list", store: store)
        let live = [Record(id: 3, name: "Live")]
        XCTAssertTrue(list.save(live))
        let original = Data(#"[{"id":1,"name":"Original"}]"#.utf8)
        store.set(original, forKey: "list.recovery")
        let copy = try XCTUnwrap(list.recoveryCopy())

        let replacement = Data(#"[{ "name": "Original", "id": 1 }]"#.utf8)
        store.set(replacement, forKey: "list.recovery")
        XCTAssertNil(list.restoreRecovery(copy))
        XCTAssertEqual(loaded(list.load()), live)
        XCTAssertEqual(list.recoveryCopies, [replacement])
    }

    func testCopyCannotRestoreInAnotherStoreOrKey() throws {
        let personal = InMemoryStore()
        let demo = InMemoryStore()
        let original = try JSONEncoder().encode([Record(id: 1, name: "Original")])
        personal.set(original, forKey: "list.recovery")
        personal.set(original, forKey: "other.recovery")
        demo.set(original, forKey: "list.recovery")
        let list = RecoverableJSONList<Record>(key: "list", store: personal)
        let demoList = RecoverableJSONList<Record>(key: "list", store: demo)
        let otherList = RecoverableJSONList<Record>(key: "other", store: personal)
        let copy = try XCTUnwrap(list.recoveryCopy())

        XCTAssertNil(demoList.restoreRecovery(copy))
        XCTAssertNil(otherList.restoreRecovery(copy))
        XCTAssertNil(demo.data(forKey: "list"))
        XCTAssertNil(personal.data(forKey: "other"))
        XCTAssertEqual(demoList.recoveryCopies, [original])
        XCTAssertEqual(otherList.recoveryCopies, [original])
    }

    func testDiscardLeavesLiveDataUntouched() throws {
        let store = InMemoryStore()
        let list = RecoverableJSONList<Record>(key: "list", store: store)
        let live = [Record(id: 4, name: "Four")]
        XCTAssertTrue(list.save(live))
        store.set(Data("broken".utf8), forKey: "list.recovery")
        list.discardRecovery()
        XCTAssertFalse(list.hasRecovery)
        XCTAssertEqual(loaded(list.load()), live)
    }

    func testUnreadableRecoveryCanBeDiscarded() throws {
        let store = InMemoryStore()
        let list = RecoverableJSONList<Record>(key: "list", store: store)
        store.set(Data("broken live".utf8), forKey: "list")
        store.set(Data("broken recovery".utf8), forKey: "list.recovery")
        _ = list.load()
        XCTAssertTrue(list.hasRecovery)
        XCTAssertNil(list.recovery())
        XCTAssertNil(list.restoreRecovery())
        list.discardRecovery()
        XCTAssertFalse(list.hasRecovery)
    }
}
