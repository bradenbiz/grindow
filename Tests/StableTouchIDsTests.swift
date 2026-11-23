import XCTest
@testable import GrindowCore

final class StableTouchIDsTests: XCTestCase {
    func testFingersKeepTheirIDsWhileTouching() {
        var ids = StableTouchIDs<String>()
        let first = ids.ids(for: ["a", "b", "c"])
        XCTAssertEqual(Set(first).count, 3)
        // Order of the frame may change; IDs follow the finger, not the slot.
        XCTAssertEqual(ids.ids(for: ["c", "a", "b"]), [first[2], first[0], first[1]])
    }

    func testLiftedFingerGetsANewIDWhenItLandsAgain() {
        var ids = StableTouchIDs<String>()
        let first = ids.ids(for: ["a", "b", "c"])
        _ = ids.ids(for: ["a", "b"])
        let again = ids.ids(for: ["a", "b", "c"])
        XCTAssertEqual(Array(again.prefix(2)), Array(first.prefix(2)))
        XCTAssertNotEqual(again[2], first[2])
    }

    /// A lifted-and-replaced finger changes the ID set, so the recognizer
    /// restarts instead of measuring from the old finger's start point.
    func testReplacedFingerRestartsRecognizer() {
        var ids = StableTouchIDs<String>()
        var recognizer = ThreeFingerSwipeRecognizer()
        func frame(_ keys: [String], y: Float) -> ThreeFingerSwipeRecognizer.Event? {
            let points = zip(ids.ids(for: keys), keys.indices).map { TouchPoint(id: $0, x: Float($1) * 0.1, y: y) }
            return recognizer.process(points)
        }
        XCTAssertEqual(frame(["a", "b", "c"], y: 0.5), .began)
        XCTAssertEqual(frame(["a", "b", "d"], y: 0.5), .began)
        XCTAssertEqual(frame(["a", "b", "d"], y: 0.6), .swipe(.up))
    }
}
