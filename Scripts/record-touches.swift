#!/usr/bin/env swift
// Records real trackpad gestures as test fixtures for ThreeFingerSwipeRecognizer.
//
// Run on a Mac from the repo root, with Grindow quit so it doesn't act on the
// gestures:
//
//   swift Scripts/record-touches.swift                      # every scenario
//   swift Scripts/record-touches.swift four-staggered-up    # just these
//
// Each gesture is saved to Tests/Fixtures/Touches/<scenario>.json and replayed by
// TouchReplayTests, which holds the expected outcome for each scenario. macOS
// still acts on the gestures while recording, so expect Spaces to move.

import Foundation

// MARK: - Scenarios (names must match TouchReplayTests.expectations)

let scenarios: [(name: String, instruction: String)] = [
    ("three-up", "Swipe up with three fingers."),
    ("three-down", "Swipe down with three fingers."),
    ("three-left", "Swipe left with three fingers."),
    ("three-right", "Swipe right with three fingers."),
    ("three-slow-up", "Swipe up with three fingers slowly, taking about a second."),
    ("three-small", "Put three fingers down, move them less than half a centimetre, and lift."),
    ("two-scroll", "Scroll up with two fingers."),
    ("four-up", "Swipe up with four fingers, landing them together as you normally would."),
    ("four-staggered-up", "Put three fingers down, add a fourth a moment later, then swipe up with all four."),
    ("four-staggered-left", "Put three fingers down, add a fourth a moment later, then swipe left with all four."),
    ("four-lift-early", "Swipe up with four fingers, lifting one finger about halfway through.")
]

// MARK: - MultitouchSupport (private; loaded at runtime)

// Same layout as GestureInterceptor's MTTouch (96 bytes).
struct MTReadout { var posX: Float; var posY: Float; var velX: Float; var velY: Float }
struct MTTouch {
    var frame: Int32
    var _pad0: Int32
    var timestamp: Double
    var identifier: Int32
    var state: Int32   // 1=not touching, 4=touching, 6/7=lifted
    var fingerIdx: Int32
    var handIdx: Int32
    var normalized: MTReadout
    var size: Float
    var reserved1: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var absolute: MTReadout
    var reserved2: Int32
    var reserved3: Int32
    var zDensity: Float
}

typealias MTDeviceRef = UnsafeMutableRawPointer
typealias ContactCallback = @convention(c) (Int32, UnsafeMutableRawPointer?, Int32, Double, Int32) -> Int32

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("record-touches: \(message)\n".utf8))
    exit(1)
}

guard MemoryLayout<MTTouch>.size == 96 else { fail("MTTouch is \(MemoryLayout<MTTouch>.size) bytes, expected 96") }
guard let framework = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW) else {
    fail("could not load MultitouchSupport")
}

func symbol<T>(_ name: String, as type: T.Type) -> T {
    guard let pointer = dlsym(framework, name) else { fail("missing symbol \(name)") }
    return unsafeBitCast(pointer, to: type)
}

let MTDeviceCreateDefault = symbol("MTDeviceCreateDefault", as: (@convention(c) () -> MTDeviceRef?).self)
let MTRegisterContactFrameCallback = symbol("MTRegisterContactFrameCallback",
                                            as: (@convention(c) (MTDeviceRef, ContactCallback) -> Void).self)
let MTDeviceStart = symbol("MTDeviceStart", as: (@convention(c) (MTDeviceRef, Int32) -> Int32).self)

// MARK: - Recording

struct RecordedTouch: Codable { let id: Int32; let state: Int32; let x: Float; let y: Float }
struct RecordedFrame: Codable { let t: Double; let touches: [RecordedTouch] }
struct Recording: Codable {
    let scenario: String
    let instruction: String
    let macOS: String
    let recordedAt: String
    let frames: [RecordedFrame]
}

/// Collects frames from MultitouchSupport's thread while a gesture is being recorded.
final class Recorder {
    private let lock = NSLock()
    private var isRecording = false
    private var frames: [(time: Double, touches: [RecordedTouch])] = []
    private var lastContactUptime: TimeInterval?

    func begin() {
        lock.lock(); defer { lock.unlock() }
        frames = []
        lastContactUptime = nil
        isRecording = true
    }

    func append(time: Double, touches: [RecordedTouch]) {
        lock.lock(); defer { lock.unlock() }
        guard isRecording else { return }
        let inContact = touches.contains { $0.state == 4 }
        // Skip idle frames before the first finger lands.
        guard inContact || lastContactUptime != nil else { return }
        frames.append((time, touches))
        if inContact { lastContactUptime = ProcessInfo.processInfo.systemUptime }
    }

    /// Seconds since a finger was last in contact, or nil before the first contact.
    var secondsSinceLastContact: TimeInterval? {
        lock.lock(); defer { lock.unlock() }
        return lastContactUptime.map { ProcessInfo.processInfo.systemUptime - $0 }
    }

    /// Stops recording; keeps frames up to the first one after every finger lifted.
    func finish() -> [RecordedFrame] {
        lock.lock(); defer { lock.unlock() }
        isRecording = false
        guard let start = frames.first?.time,
              let last = frames.lastIndex(where: { $0.touches.contains { $0.state == 4 } }) else { return [] }
        let end = min(last + 1, frames.count - 1)
        return frames[...end].map { RecordedFrame(t: ($0.time - start).rounded(places: 4), touches: $0.touches) }
    }
}

enum Shared {
    static let recorder = Recorder()
}

extension Double {
    func rounded(places: Int) -> Double {
        let scale = pow(10, Double(places))
        return (self * scale).rounded() / scale
    }
}

let contactCallback: ContactCallback = { _, raw, count, timestamp, _ in
    let n = raw == nil ? 0 : Int(max(0, count))
    let touches = UnsafeBufferPointer<MTTouch>(
        start: raw.map { UnsafePointer($0.assumingMemoryBound(to: MTTouch.self)) }, count: n
    ).map {
        RecordedTouch(id: $0.identifier, state: $0.state,
                      x: Float(Double($0.normalized.posX).rounded(places: 4)),
                      y: Float(Double($0.normalized.posY).rounded(places: 4)))
    }
    Shared.recorder.append(time: timestamp, touches: touches)
    return 0
}

func recordGesture() -> [RecordedFrame] {
    Shared.recorder.begin()
    // The gesture ends once no finger has touched the pad for half a second.
    while (Shared.recorder.secondsSinceLastContact ?? 0) < 0.5 {
        Thread.sleep(forTimeInterval: 0.02)
    }
    return Shared.recorder.finish()
}

// MARK: - Main

let outputDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Tests/Fixtures/Touches")
guard FileManager.default.fileExists(atPath: "Package.swift") else { fail("run this from the repo root") }

let requested = Array(CommandLine.arguments.dropFirst())
let unknown = requested.filter { name in !scenarios.contains { $0.name == name } }
guard unknown.isEmpty else {
    fail("unknown scenario(s): \(unknown.joined(separator: ", ")). Known: \(scenarios.map(\.name).joined(separator: ", "))")
}
let selected = requested.isEmpty ? scenarios : scenarios.filter { requested.contains($0.name) }

guard let device = MTDeviceCreateDefault() else { fail("no multitouch device found") }
MTRegisterContactFrameCallback(device, contactCallback)
guard MTDeviceStart(device, 0) == 0 else { fail("MTDeviceStart failed") }
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let encoder = JSONEncoder()
encoder.outputFormatting = [.sortedKeys]
let timestampFormatter = ISO8601DateFormatter()

print("Recording \(selected.count) gesture(s). Quit Grindow first so it doesn't act on them.\n")
for (index, scenario) in selected.enumerated() {
    while true {
        print("[\(index + 1)/\(selected.count)] \(scenario.name): \(scenario.instruction)")
        print("Press Enter, then do the gesture.", terminator: " ")
        _ = readLine()
        let frames = recordGesture()
        let maxFingers = frames.map { $0.touches.filter { $0.state == 4 }.count }.max() ?? 0
        let duration = frames.last?.t ?? 0
        print("Captured \(frames.count) frames over \(String(format: "%.2f", duration)) s, up to \(maxFingers) finger(s).")
        print("Keep it? [Y/n]", terminator: " ")
        if readLine()?.lowercased().hasPrefix("n") == true {
            print("Discarded; try again.\n")
            continue
        }
        let recording = Recording(scenario: scenario.name, instruction: scenario.instruction,
                                  macOS: ProcessInfo.processInfo.operatingSystemVersionString,
                                  recordedAt: timestampFormatter.string(from: Date()), frames: frames)
        let file = outputDirectory.appendingPathComponent("\(scenario.name).json")
        try encoder.encode(recording).write(to: file)
        print("Saved \(file.path)\n")
        break
    }
}
print("Done. Run `swift test` to replay the recordings.")
exit(0)
