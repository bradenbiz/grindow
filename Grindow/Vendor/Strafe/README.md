# Strafe code used by Grindow

Source: https://github.com/rileycx/strafe
Pinned commit: 37ec57e0dd7ae91c22225bc36bf5cd210ff9cba7

CStrafe.c/.h and IOHIDPayload.c/.h are copied from this revision. LICENSE contains
Strafe's MIT notice, InstantSpaceSwitcher's MIT notice, and joshuarli/iss's 0BSD
notice. The license is also copied into the built app's Resources directory.

Local changes: synthesis functions take a CGPoint and apply it to every event,
including macOS 27 companion events. This pins a gesture sequence to the selected
display without moving the user's pointer. Live multi-monitor routing still
requires validation on the target macOS release. Grindow uses its own topology
parser and verified switch coordinator; the upstream topology/inspection helpers
are retained to make future comparisons straightforward. No upstream event tap,
CLI, hotkey registration, install script, or preferences code is run.

SpaceManager's animation ramp is adapted from Strafe's SwitchEngine.swift and
TransitionSpeed.swift: six progress steps to 0.35, end velocity 130, with 30 ms and
60 ms ramp choices. Grindow sends cancellation if an animated sequence is aborted.

Multi-Space dispatch now follows `iss_switch_to_index` in
https://github.com/jurplel/InstantSpaceSwitcher/blob/main/Sources/ISS/ISS.c
(reviewed 2026-09-28): post all required gestures synchronously and scale velocity
by distance. The local helper caps velocity at 30000 for the signed 16.16 macOS 27
payload and rejects counts outside 1...128. Swift verifies the destination after
the burst instead of waiting at every intermediate Space. This does not establish
an atomic jump or guarantee that WindowServer never paints an intermediate frame.

`sh Scripts/test-native.sh` redirects CGEventPost to a test observer and verifies
phase ordering, burst length, velocity, bounds, and event coordinates without
sending gestures to macOS.

These interfaces are private and version-sensitive. The copied code includes the
macOS 27 IOHID format branch, but Grindow's local build/test environment is macOS
26.2. Automated navigation tests do not establish live OS gesture compatibility.
