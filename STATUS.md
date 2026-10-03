# Grindow — Status (2026-09-28)

## Current switching implementation

Grindow uses Strafe-derived synthetic Dock-swipe events through macOS's native
transition path. Source provenance and license notices are in
`Grindow/Vendor/Strafe/README.md` and `LICENSE`; the license ships in app Resources.

Each connected display has its own ordered Space roster, current Space, saved grid
layout, and display picker. Gestures select the display under the pointer when
tracking starts. Disconnected display rosters are excluded. The grid expands to
show all Spaces if the selected dimensions are too small.

All four swipe directions are inverted by default: fingers up navigate down,
down navigate up, left navigate right, and right navigate left. Settings offers
one Invert all swipe directions toggle for both axes. Cell clicks are unchanged.

Swipes now show a centered translucent grid HUD on the selected display. It marks
the requested destination while switching, then reflects the confirmed position.
The HUD also appears at grid edges, holds for 900 ms after the most recent swipe,
and fades out over 160 ms. Its nonactivating panel ignores mouse events and cannot
become key or main; it joins Spaces and supports full-screen auxiliary display.
Settings → Space Switching → Show grid after swiping disables it. Reduce Motion
removes the fade; Reduce Transparency uses a solid background. No capture is used.

Adjacent navigation supports Instant, Quick, and Smooth animation. Nonadjacent
navigation follows InstantSpaceSwitcher's `iss_switch_to_index`: send all required
adjacent gestures synchronously, with velocity scaled by distance, then verify the
final destination. Intermediate states may be observed during verification but
are not deliberately waited on before posting the next gesture. Pending requests
wait for the dispatched burst to land before posting another route. The UI shows
observed active state rather than pretending the requested destination is active.

Timeouts, unexpected topology changes, overshoot, reversal, unavailable displays,
and event creation failure stop navigation. Failed or partially landed bursts are
not automatically resent, since the original events could still be in flight.
Cancellation prevents further bursts; events already posted cannot be recalled.

## User-reported runtime evidence

- Accessibility setup worked after granting the rebuilt app access.
- Clicking destination cells works.
- The original sequential, verified-hop implementation flashed intervening
  desktops on longer jumps (for example, 6 → 4).
- The subsequent screenshot-cover workaround was glitchy and added latency.
  It has been removed entirely, including capture APIs, permission polling,
  settings, and UI. This build does not use Screen Recording.
- The new burst implementation removes our per-hop delays but is still multiple
  native gestures, not an atomic direct-to-Space API. Elimination of intermediate
  frames remains unproven and must not be claimed from unit-test results.
- The user reports swiping works well once underway, with some initial glitches.
  Startup investigation is deferred at the user's request.

## Verification

- Debug arm64 Xcode build succeeded on macOS 26.2 / Swift 6.3.3.
- Overlay-only AppKit harness passed on the desktop: foreground app preserved,
  non-key/main and mouse passthrough flags checked, rapid repeated presentation
  survived the earlier dismissal deadline, and final dismissal completed. Rendered
  grid was visually inspected. Actual Space-transition/full-screen behavior of
  the HUD still needs live validation.
- 13 Swift tests passed for display-local topology, ghost filtering, grid routing,
  layout reconciliation, one-burst jumps in both directions, intermediate
  observations, partial-landing timeout, overshoot, queued reversal, post failure,
  no-op navigation, topology changes, and cancellation.
- Native C burst tests passed with CGEventPost replaced by a recorder. Checks
  complete began/changed/ended sequences, event count, direction/velocity,
  coordinates on a display left of the main display, and count bounds.
- Local certificate signing is configured with `Grindow Local Development` in the
  user keychain. Build using `sh Scripts/build-local.sh`; do not ad-hoc re-sign the
  output. See `Scripts/LOCAL-SIGNING.md`. Two fresh builds passed with different
  code hashes and identical certificate-backed designated requirements. The second
  passed strict nested signature verification against the first build's identity.
  The signed output is `build/Grindow.app`. After switching from the old ad-hoc
  build, Accessibility needs one final grant; retention across later updates still
  needs live confirmation.

Run checks:

```sh
swift test
sh Scripts/test-native.sh
sh Scripts/build-local.sh
```

## Setup and remaining live checks

Grant Accessibility and turn off native three-finger Swipe between full-screen
apps, Mission Control, and App Exposé (or assign them to four fingers). Grindow
retains raw MultitouchSupport recognition; no native event interception is included.

Retest 6 → 4 and longer row jumps for speed, destination accuracy, and intermediate
flashing. Check all three monitors, including selected-display clicks when the
pointer is on another monitor. The explicit event-coordinate routing is a local
adaptation beyond upstream Strafe and still needs full validation.

Full-screen entry/exit, minimizing/restoring, Desktop 1 navigation, and Brave redraw
issues from the earlier direct-CGS backend are not yet proven fixed. Test rapid
swipes/reversals, display disconnects, native Mission Control, and permission
revocation. The macOS 27 payload branch is included but untested here; older macOS
versions also require runtime compatibility testing.

Desktop creation and vertical slide animations remain unimplemented. Grid rows
are Grindow's navigation model; the underlying native transitions are horizontal.
