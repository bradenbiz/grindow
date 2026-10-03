import XCTest
@testable import GrindowCore

/// Replays real gestures recorded by `Scripts/record-touches.swift` through the
/// recognizer, so tests use real finger timing instead of scripted frames.
final class TouchReplayTests: XCTestCase {
    private struct Recording: Decodable {
        struct Touch: Decodable { let id: Int32; let state: Int32; let x: Float; let y: Float }
        struct Frame: Decodable { let t: Double; let touches: [Touch] }
        let scenario: String
        let frames: [Frame]
    }

    private struct Expectation {
        let swipes: [SwipeDirection]
        /// Set while a known bug makes this scenario fail; the failure is expected.
        var knownIssue: String? = nil
    }

    private static let fourFingerIssue = "A four-finger gesture can pass through a three-finger state (fixed in #4)"

    /// Expected swipes per scenario. Names match the recording script.
    private static let expectations: [String: Expectation] = [
        "three-up": Expectation(swipes: [.up]),
        "three-down": Expectation(swipes: [.down]),
        "three-left": Expectation(swipes: [.left]),
        "three-right": Expectation(swipes: [.right]),
        "three-slow-up": Expectation(swipes: [.up]),
        "three-small": Expectation(swipes: []),
        "two-scroll": Expectation(swipes: []),
        "four-up": Expectation(swipes: [], knownIssue: fourFingerIssue),
        "four-staggered-up": Expectation(swipes: [], knownIssue: fourFingerIssue),
        "four-staggered-left": Expectation(swipes: [], knownIssue: fourFingerIssue),
        "four-lift-early": Expectation(swipes: [], knownIssue: fourFingerIssue)
    ]

    private let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Touches")

    private func swipes(in recording: Recording) -> [SwipeDirection] {
        var recognizer = ThreeFingerSwipeRecognizer()
        return recording.frames.compactMap { frame in
            let contacts = frame.touches.filter { $0.state == 4 }.map { TouchPoint(id: $0.id, x: $0.x, y: $0.y) }
            guard case .swipe(let direction)? = recognizer.process(contacts) else { return nil }
            return direction
        }
    }

    func testRecordedGestures() throws {
        let files = ((try? FileManager.default.contentsOfDirectory(at: fixtures, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        try XCTSkipIf(files.isEmpty, "No recordings yet; run `swift Scripts/record-touches.swift` on a Mac.")

        for file in files {
            let recording = try JSONDecoder().decode(Recording.self, from: Data(contentsOf: file))
            guard let expected = Self.expectations[recording.scenario] else {
                XCTFail("\(file.lastPathComponent): no expectation for scenario \(recording.scenario)")
                continue
            }
            let actual = swipes(in: recording)
            if let issue = expected.knownIssue {
                XCTExpectFailure(issue, strict: false) {
                    XCTAssertEqual(actual, expected.swipes, recording.scenario)
                }
            } else {
                XCTAssertEqual(actual, expected.swipes, recording.scenario)
            }
        }
    }
}
