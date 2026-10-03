import XCTest
@testable import GrindowCore

final class NavigationTests: XCTestCase {
    func testDisplayTopologyDoesNotUseAnotherDisplaysActiveSpace() {
        func entry(_ id: UInt64, _ type: Int = 0) -> [String: Any] { ["id64": id, "type": type] }
        let roster: [[String: Any]] = [
            ["Display Identifier": "Main", "Spaces": [entry(3), entry(4, 4)], "Current Space": ["id64": 4]],
            ["Display Identifier": "external", "Spaces": [entry(8), entry(9)], "Current Space": ["id64": 8]],
            ["Display Identifier": "ghost", "Spaces": [entry(99)], "Current Space": ["id64": 99]]
        ]
        let displays = DisplaySpaces.parse(roster, connected: ["main": "Built-in", "external": "External"], mainDisplayID: "main")
        XCTAssertEqual(displays.map(\.currentSpaceID), [4, 8])
        XCTAssertEqual(displays[0].spaces.map(\.id), [3, 4])
        XCTAssertEqual(displays[1].spaces.first?.index, 0)
        var missing = roster[1]
        missing.removeValue(forKey: "Current Space")
        XCTAssertEqual(DisplaySpaces.parse([missing], connected: ["external": "External"], mainDisplayID: "main").first?.currentSpaceID, 0)
    }

    func testGridDoesNotLoseSpacesAndRoutesVerticalAndWrap() {
        let grid = SpaceGrid()
        grid.arrange(spaceIDs: [1, 2, 3, 4, 5, 6, 7], rows: 2, columns: 3)
        XCTAssertEqual(grid.rows, 3)
        XCTAssertEqual(grid.spaceID(at: GridPosition(row: 2, column: 0)), 7)
        XCTAssertEqual(grid.targetPosition(from: .init(row: 0, column: 1), direction: .down, edgeBehavior: .stop), .init(row: 1, column: 1))
        XCTAssertEqual(grid.targetPosition(from: .init(row: 0, column: 0), direction: .left, edgeBehavior: .wrap), .init(row: 0, column: 2))
        XCTAssertNil(grid.targetPosition(from: .init(row: 2, column: 0), direction: .right, edgeBehavior: .stop))
        grid.updateCurrentPosition(forSpaceID: 99)
        XCTAssertEqual(grid.currentPosition, .init(row: -1, column: -1))
    }

    func testSavedLayoutKeepsOrderAndReplacesRemovedOrDuplicateSpaces() {
        XCTAssertEqual(AppSettings.reconcile(saved: [3, 1, 0, 99, 1], liveIDs: [1, 2, 3, 4]), [3, 1, 2, 4])
        XCTAssertEqual(AppSettings.reconcile(saved: [99, 0], liveIDs: []), [])
        XCTAssertEqual(AppSettings.reconcile(saved: [], liveIDs: [8, 9]), [8, 9])
    }

    @MainActor
    func testLongJumpIsOneBurstAndVerifiesFinalDestination() async {
        let backend = Backend()
        let worker = backend.worker()
        let finished = expectation(description: "finished")
        worker.onFinish = { error in XCTAssertNil(error); finished.fulfill() }
        XCTAssertTrue(worker.request(target: 4, display: "A"))
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(backend.posts, [3])
        XCTAssertEqual(backend.current, 4)
        XCTAssertNil(worker.targetID)
    }

    @MainActor
    func testLeftwardJumpUsesOneNegativeBurst() async {
        let backend = Backend(); backend.current = 4
        let worker = backend.worker()
        let finished = expectation(description: "left")
        worker.onFinish = { error in XCTAssertNil(error); finished.fulfill() }
        XCTAssertTrue(worker.request(target: 2, display: "A"))
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(backend.posts, [-2])
        XCTAssertEqual(backend.current, 2)
    }

    @MainActor
    func testIntermediateSpacesDoNotCauseAdditionalPosts() async {
        let backend = Backend(); backend.land = false
        // The first read after dispatch still reports the starting Space, then
        // the intermediate Spaces, then the destination. No per-hop dispatch.
        backend.observations = [1, 2, 3, 4]
        let worker = backend.worker()
        let finished = expectation(description: "intermediate")
        worker.onFinish = { error in XCTAssertNil(error); finished.fulfill() }
        XCTAssertTrue(worker.request(target: 4, display: "A"))
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(backend.posts, [3])
        XCTAssertEqual(backend.current, 4)
    }

    @MainActor
    func testPartialLandingTimesOutWithoutRepostingBurst() async {
        let backend = Backend(); backend.land = false; backend.observations = [2]
        let worker = backend.worker()
        let finished = expectation(description: "timeout")
        worker.onFinish = { error in
            guard case SpaceSwitchCoordinator.Failure.timedOut? = error else { return XCTFail("Expected timeout") }
            finished.fulfill()
        }
        XCTAssertTrue(worker.request(target: 4, display: "A"))
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(backend.posts, [3])
        XCTAssertEqual(backend.current, 2)
    }

    @MainActor
    func testOvershootStopsWithoutCorrectiveGestures() async {
        let backend = Backend(); backend.land = false; backend.observations = [4]
        let worker = backend.worker()
        let finished = expectation(description: "overshoot")
        worker.onFinish = { error in
            guard case SpaceSwitchCoordinator.Failure.changed? = error else { return XCTFail("Expected unexpected landing") }
            finished.fulfill()
        }
        XCTAssertTrue(worker.request(target: 3, display: "A"))
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(backend.posts, [2])
    }

    @MainActor
    func testRetargetWaitsForOriginalBurstToLand() async {
        let backend = Backend(); backend.land = false
        let worker = backend.worker()
        let posted = expectation(description: "first burst posted")
        backend.onPost = { posted.fulfill() }
        let finished = expectation(description: "reverse completed")
        worker.onFinish = { error in XCTAssertNil(error); finished.fulfill() }
        XCTAssertTrue(worker.request(target: 4, display: "A"))
        await fulfillment(of: [posted], timeout: 2)
        XCTAssertTrue(worker.request(target: 1, display: "A"))
        XCTAssertFalse(worker.request(target: 2, display: "B"))
        XCTAssertEqual(backend.posts, [3])
        backend.onPost = {}
        backend.current = 4
        backend.land = true
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(backend.posts, [3, -3])
        XCTAssertEqual(backend.current, 1)
    }

    @MainActor
    func testPostFailureDoesNotAdvance() async {
        let backend = Backend()
        let worker = backend.worker()
        worker.post = { _, _, _ in throw SpaceSwitchCoordinator.Failure.postFailed }
        let finished = expectation(description: "post failed")
        worker.onFinish = { error in XCTAssertNotNil(error); finished.fulfill() }
        XCTAssertFalse(worker.request(target: 99, display: "A"))
        XCTAssertTrue(worker.request(target: 3, display: "A"))
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(backend.current, 1)
        XCTAssertNil(worker.targetID)
    }

    @MainActor
    func testSameDestinationDoesNotPost() async {
        let backend = Backend()
        let worker = backend.worker()
        let finished = expectation(description: "no-op")
        worker.onFinish = { error in XCTAssertNil(error); finished.fulfill() }
        XCTAssertTrue(worker.request(target: 1, display: "A"))
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertTrue(backend.posts.isEmpty)
    }

    @MainActor
    func testTopologyChangeAbortsRoute() async {
        let backend = Backend(); backend.removeAfterPost = true
        let worker = backend.worker()
        let finished = expectation(description: "changed")
        worker.onFinish = { error in XCTAssertNotNil(error); finished.fulfill() }
        XCTAssertTrue(worker.request(target: 4, display: "A"))
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(backend.posts, [3])
    }

    @MainActor
    func testCancellationDoesNotPost() async {
        let backend = Backend()
        let worker = backend.worker()
        let finished = expectation(description: "cancelled")
        worker.onFinish = { _ in finished.fulfill() }
        XCTAssertTrue(worker.request(target: 4, display: "A"))
        worker.cancel()
        XCTAssertFalse(worker.request(target: 2, display: "A"))
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertTrue(backend.posts.isEmpty)
    }
}

@MainActor
private final class Backend {
    var current: UInt64 = 1
    var ids: [UInt64] = [1, 2, 3, 4]
    var posts: [Int] = []
    var land = true
    var observations: [UInt64] = []
    var removeAfterPost = false
    var onPost: () -> Void = {}
    func worker() -> SpaceSwitchCoordinator {
        SpaceSwitchCoordinator(attempts: 20, pollNanoseconds: 1_000_000, snapshot: { display in
            if !self.posts.isEmpty, !self.observations.isEmpty { self.current = self.observations.removeFirst() }
            return DisplaySpaces(id: display, name: display, spaces: self.ids.enumerated().map { index, id in
                SpaceInfo(id: id, index: index, type: .desktop, displayUUID: display, label: "")
            }, currentSpaceID: self.current)
        }, post: { right, _, steps in
            self.posts.append(right ? steps : -steps)
            if self.land { self.current = right ? self.current + UInt64(steps) : self.current - UInt64(steps) }
            if self.removeAfterPost { self.ids.removeLast() }
            self.onPost()
        })
    }
}
