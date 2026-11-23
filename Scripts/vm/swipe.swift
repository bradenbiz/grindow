// Posts fake three-finger swipes to a Debug build of Grindow, which has no
// trackpad to read in the VM: `swipe <up|down|left|right>[,<dir>...] [N] [interval-ms]`.
// Each direction is sent N times, `interval-ms` apart, in order, so
// `swipe right,left 2` sends right right left left. Grindow's
// GestureInterceptor treats each one as a swipe the recognizer just saw.
// `grindow-vm swipe` compiles and runs this in the VM.
import Foundation

let args = CommandLine.arguments.dropFirst()
let valid: Set = ["up", "down", "left", "right"]
guard let first = args.first else {
    FileHandle.standardError.write("usage: swipe <up|down|left|right>[,...] [N] [interval-ms]\n".data(using: .utf8)!)
    exit(2)
}
let directions = first.split(separator: ",").map(String.init)
guard !directions.isEmpty, directions.allSatisfy(valid.contains) else {
    FileHandle.standardError.write("bad direction in \(first)\n".data(using: .utf8)!)
    exit(2)
}
let count = args.dropFirst().first.flatMap { Int($0) } ?? 1
let intervalMs = args.dropFirst(2).first.flatMap { Int($0) } ?? 300

let center = DistributedNotificationCenter.default()
var sent = 0
for direction in directions {
    for _ in 0..<count {
        if sent > 0 { usleep(useconds_t(intervalMs * 1000)) }
        center.postNotificationName(
            Notification.Name("com.grindow.debug.swipe"), object: nil,
            userInfo: ["direction": direction], deliverImmediately: true)
        sent += 1
    }
}
// Posting is asynchronous. Exiting right after a burst of back-to-back posts
// sometimes dropped the last one, so give distnoted a moment to deliver.
usleep(300_000)
