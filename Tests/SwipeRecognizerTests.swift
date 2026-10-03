import XCTest
@testable import GrindowCore

/// Drives `ThreeFingerSwipeRecognizer` with scripted touch frames, standing in
/// for a real trackpad.
final class SwipeRecognizerTests: XCTestCase {
    /// Fingers 1-3 resting side by side in the middle of the pad.
    private let rest: [TouchPoint] = [
        TouchPoint(id: 1, x: 0.4, y: 0.5),
        TouchPoint(id: 2, x: 0.5, y: 0.5),
        TouchPoint(id: 3, x: 0.6, y: 0.5)
    ]

    private func moved(_ fingers: [TouchPoint], dx: Float = 0, dy: Float = 0) -> [TouchPoint] {
        fingers.map { TouchPoint(id: $0.id, x: $0.x + dx, y: $0.y + dy) }
    }

    /// Feeds frames in order and returns every event emitted.
    private func run(_ frames: [[TouchPoint]], recognizer: inout ThreeFingerSwipeRecognizer) -> [ThreeFingerSwipeRecognizer.Event] {
        frames.compactMap { recognizer.process($0) }
    }

    private func run(_ frames: [[TouchPoint]]) -> [ThreeFingerSwipeRecognizer.Event] {
        var recognizer = ThreeFingerSwipeRecognizer()
        return run(frames, recognizer: &recognizer)
    }

    func testEachDirection() {
        XCTAssertEqual(run([rest, moved(rest, dy: 0.1)]), [.began, .swipe(.up)])
        XCTAssertEqual(run([rest, moved(rest, dy: -0.1)]), [.began, .swipe(.down)])
        XCTAssertEqual(run([rest, moved(rest, dx: 0.1)]), [.began, .swipe(.right)])
        XCTAssertEqual(run([rest, moved(rest, dx: -0.1)]), [.began, .swipe(.left)])
    }

    func testSwipeFiresOncePerGesture() {
        let frames = [rest, moved(rest, dy: 0.05), moved(rest, dy: 0.1), moved(rest, dy: 0.2), moved(rest, dy: 0.3)]
        XCTAssertEqual(run(frames), [.began, .swipe(.up)])
    }

    func testShortMovementDoesNotFire() {
        XCTAssertEqual(run([rest, moved(rest, dy: 0.07)]), [.began])
    }

    func testDiagonalMovementDoesNotFire() {
        XCTAssertEqual(run([rest, moved(rest, dx: 0.1, dy: 0.1)]), [.began])
        // One axis at least 1.5x the other still fires.
        XCTAssertEqual(run([rest, moved(rest, dx: 0.05, dy: 0.09)]), [.began, .swipe(.up)])
    }

    func testOtherFingerCountsAreIgnored() {
        let two = Array(rest.prefix(2))
        let four = rest + [TouchPoint(id: 4, x: 0.7, y: 0.5)]
        XCTAssertEqual(run([two, moved(two, dy: 0.2)]), [])
        XCTAssertEqual(run([four, moved(four, dy: 0.2)]), [])
    }

    func testLiftingAndTouchingAgainStartsANewGesture() {
        var recognizer = ThreeFingerSwipeRecognizer()
        XCTAssertEqual(run([rest, moved(rest, dy: 0.1), []], recognizer: &recognizer), [.began, .swipe(.up)])
        XCTAssertFalse(recognizer.isTracking)
        XCTAssertEqual(run([rest, moved(rest, dx: -0.1)], recognizer: &recognizer), [.began, .swipe(.left)])
    }

    func testFingerSwapRestartsFromNewPositions() {
        // Finger 3 is replaced by finger 9 after the hand already moved up 0.05.
        let swapped = moved(Array(rest.prefix(2)), dy: 0.05) + [TouchPoint(id: 9, x: 0.6, y: 0.55)]
        // Measured from the swap, 0.05 more is below the threshold...
        XCTAssertEqual(run([rest, moved(rest, dy: 0.05), swapped, moved(swapped, dy: 0.05)]), [.began, .began])
        // ...and 0.1 more fires.
        XCTAssertEqual(run([rest, swapped, moved(swapped, dy: 0.1)]), [.began, .began, .swipe(.up)])
    }

    func testResetStopsTracking() {
        var recognizer = ThreeFingerSwipeRecognizer()
        _ = recognizer.process(rest)
        recognizer.reset()
        XCTAssertFalse(recognizer.isTracking)
        XCTAssertEqual(recognizer.process(moved(rest, dy: 0.2)), .began)
    }
}
