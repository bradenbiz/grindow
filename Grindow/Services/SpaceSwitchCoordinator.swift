import Foundation

/// Posts an entire route as one burst, then verifies its destination. Pending
/// requests are serialized behind that confirmation; failed bursts are not retried.
@MainActor
final class SpaceSwitchCoordinator {
    enum Failure: Error, LocalizedError {
        case unavailable, changed, timedOut, postFailed
        var errorDescription: String? {
            switch self {
            case .unavailable: return "The selected display or Space is no longer available."
            case .changed: return "Spaces changed during navigation. Try again."
            case .timedOut: return "macOS did not confirm the requested destination. Navigation stopped; try the destination again."
            case .postFailed: return "The Space-switch gesture could not be sent."
            }
        }
    }

    var snapshot: (String) -> DisplaySpaces?
    /// right, display UUID, number of adjacent Spaces to traverse.
    var post: (Bool, String, Int) async throws -> Void
    var onFinish: (Error?) -> Void = { _ in }
    var onProgress: () -> Void = {}
    private(set) var targetID: UInt64?
    private(set) var displayID: String?
    private var task: Task<Void, Never>?
    /// Bumped when a new task replaces a cancelled one, so the cancelled task's
    /// cleanup doesn't clear the replacement's state or report its finish.
    private var generation = 0
    private let attempts: Int
    private let pollNanoseconds: UInt64

    init(attempts: Int = 50, pollNanoseconds: UInt64 = 20_000_000,
         snapshot: @escaping (String) -> DisplaySpaces?,
         post: @escaping (Bool, String, Int) async throws -> Void) {
        self.attempts = attempts
        self.pollNanoseconds = pollNanoseconds
        self.snapshot = snapshot
        self.post = post
    }

    @discardableResult
    func request(target: UInt64, display: String) -> Bool {
        let cancelled = task?.isCancelled == true
        guard task == nil || cancelled || displayID == display,
              let info = snapshot(display), info.spaces.contains(where: { $0.id == target }),
              info.spaces.contains(where: { $0.id == info.currentSpaceID }) else { return false }
        targetID = target
        displayID = display
        if task != nil, !cancelled { return true }
        // A cancelled task may still be closing its gesture; start once it ends.
        let previous = task
        generation += 1
        let current = generation
        task = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            var error: Error?
            do { try await self.navigate(display: display) }
            catch is CancellationError { }
            catch let failure { error = failure }
            guard self.generation == current else { return }
            self.targetID = nil
            self.displayID = nil
            self.task = nil
            self.onFinish(error)
        }
        return true
    }

    func cancel() { task?.cancel() }

    private func navigate(display: String) async throws {
        for _ in 0..<128 {
            try Task.checkCancellation()
            guard let state = snapshot(display), let dispatchedTarget = targetID,
                  let from = state.spaces.firstIndex(where: { $0.id == state.currentSpaceID }),
                  let to = state.spaces.firstIndex(where: { $0.id == dispatchedTarget }) else { throw Failure.unavailable }
            if from == to { return }
            let steps = abs(to - from)
            guard steps <= 128 else { throw Failure.unavailable }
            let roster = state.spaces.map(\.id)
            try await post(to > from, display, steps)

            // Intermediate state is allowed while macOS processes the burst. It
            // must progress toward this burst's destination, never overshoot or
            // reverse. A newly requested target waits until this burst lands.
            var landed = false
            var lastIndex = from
            for _ in 0..<attempts {
                try Task.checkCancellation()
                guard let live = snapshot(display) else { throw Failure.unavailable }
                guard live.spaces.map(\.id) == roster,
                      let index = roster.firstIndex(of: live.currentSpaceID),
                      (to > from ? (lastIndex...to).contains(index) : (to...lastIndex).contains(index)) else {
                    throw Failure.changed
                }
                lastIndex = index
                if live.currentSpaceID == dispatchedTarget { landed = true; onProgress(); break }
                try await Task.sleep(nanoseconds: pollNanoseconds)
            }
            // Never resend a burst: it may still be in flight in the Dock.
            guard landed else { throw Failure.timedOut }
        }
        throw Failure.timedOut
    }
}
