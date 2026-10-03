# Testing options: letting Claude verify changes without you

Status (2026-10-03): **A and B are implemented in this PR**
(`.github/workflows/ci.yml`, `Models/ThreeFingerSwipeRecognizer.swift`,
`Tests/SwipeRecognizerTests.swift`). G comes next, after PR #4 lands, because it
touches the same files. C and E are deferred. D is declined (see below).

## The problem

Claude works on a Linux machine. Grindow is a macOS-only app built on AppKit,
private MultitouchSupport, private CGS Space APIs and synthetic Dock swipes. From
there Claude can't compile it, run `swift test`, launch it, or touch a
trackpad. Today every change needs you on the Mac.

The PR #3 review shows what needs checking:

| Kind of check | Examples from the review | Needs |
|---|---|---|
| Compiles, unit tests pass | Everything. PR #4 has never been compiled | macOS + Xcode |
| Pure logic | Layout reflow (#7), coordinator cancel (#8), desktop labels (#9) | macOS + Xcode (already covered by `swift test`) |
| Gesture recognition logic | Four-finger rejection (#1), frame gating (#4) | Touch frames. Real or synthetic both work if the logic is testable |
| Real hardware and OS behavior | Sleep/wake re-attach (#2), macOS also acting on the swipe (#3), hot-plug | A real Mac, a real trackpad, a human |
| Real Space switching | Burst accuracy, intermediate flashes, multi-monitor | A logged-in GUI session with Accessibility granted |

No single option covers every row. The options below can be combined.

## Options

### A. GitHub Actions on a GitHub-hosted macOS runner

A workflow (`.github/workflows/ci.yml`) runs on every push and PR:
`swift test`, `sh Scripts/test-native.sh`, and an unsigned `xcodebuild build`
(`CODE_SIGNING_ALLOWED=NO`; once PR #4 lands, its ad-hoc default also works).
Claude pushes a branch, then reads the results with `gh run view --log-failed`.

- **Covers:** compiling, all SwiftPM tests, native C burst tests.
- **Doesn't cover:** gestures, real Space switching (runners are VMs with no
  trackpad, and Accessibility isn't granted).
- **Cost:** free. Standard GitHub-hosted runners, macOS included, are free and
  unmetered for public repos, and this repo is public. If the repo goes private,
  macOS minutes are billed at $0.062/min (2026 pricing) after the plan's included
  minutes, which count 10x for macOS. A run takes a few minutes.
- **Effort:** small. One workflow file on the `macos-26` image. The workflow
  logs the Xcode and Swift versions it used.
- **Risk:** low. Possible Xcode-version drift between your Mac and the runner.

### B. Pull gesture recognition out into a testable type

Move the frame-handling state machine out of `GestureInterceptor` (finger
count, extra-finger rejection, start/current positions, axis dominance,
threshold, invert) into a pure `ThreeFingerSwipeRecognizer` in `Models/`. It
would take `[(id, x, y)]` frames and return `SwipeDirection?`. `GestureInterceptor`
keeps only the MultitouchSupport and IOKit glue. Tests then feed it scripted
frames: "3 fingers land, 4th lands 2 frames later, all move up 0.1 → no swipe".

- **Covers:** #1, thresholds, diagonal rejection, direction mapping and inversion,
  finger-swap resets. These are exactly the bugs that are hard to reproduce by hand.
- **Doesn't cover:** whether MultitouchSupport delivers frames, struct layout,
  wake or hot-plug.
- **Cost:** none. Runs wherever `swift test` runs (A, or your Mac).
- **Effort:** small to medium. A refactor of about 150 lines, plus one
  `project.pbxproj` entry and the `Package.swift` sources list.
- **Risk:** low. Behavior should stay the same, and the tests prove it.

### C. Record and replay real touch frames

C builds on B; it doesn't replace it. B's hand-written frames stay as readable
specs for each rule. C adds real recordings, so the timing matches what your
fingers actually do.

Add a hidden debug setting that writes raw MultitouchSupport frames (id, state,
normalized position, timestamp) to a JSON file. You record the awkward gestures
once: staggered four-finger landings, fast flicks, resting a thumb, a sloppy
diagonal. Commit the recordings as test fixtures and replay them through the
recognizer from B.

- **Covers:** the same as B, but with real finger timing instead of guessed
  timing. Catches regressions when thresholds change.
- **Doesn't cover:** live OS interaction.
- **Cost:** about 10 minutes of your time per batch of recordings.
- **Effort:** medium. Needs B first, plus a recorder and a fixture loader.
- **Risk:** low. The recorder is off by default and logs only touch positions,
  no key or screen data.

### D. Give Claude a Mac to run commands on (SSH)

Enable Remote Login on your Mac, or rent a cloud Mac (for example AWS EC2 Mac
instances, which bill with a 24-hour minimum, or a hosted Mac mini). Claude
then runs `xcodebuild`, `swift test` and the native tests directly, and can
launch the app and read its logs.

- **Covers:** builds and tests with immediate feedback, plus app startup and logs.
- **Doesn't cover:** physical gestures. Real Space switching also needs a GUI
  login session and an Accessibility grant made in the GUI, which an SSH session
  doesn't give you.
- **Cost:** free on your own Mac. A cloud Mac costs real money and is mostly
  idle.
- **Effort:** small on your Mac.
- **Risk:** medium. Claude gets shell access to a machine. **Declined for now:**
  the only Mac available is the MacBook Pro you work on. A shell there could
  reach your files, and anything that switches Spaces would take over your
  screen while you type. If it's ever wanted, use a separate macOS user account
  with nothing personal in it. A covers builds and tests without any of this.

### E. Self-hosted GitHub Actions runner on your Mac

Register your Mac (ideally a separate macOS user that stays logged in) as an
Actions runner, and grant that user's runner Accessibility. Then CI can also run
**end-to-end** tests: post real synthetic Dock swipes through `SpaceManager`
and assert on `CGSCopyManagedDisplaySpaces` that the right Space became active.

- **Covers:** everything in A, plus real Space switching, burst accuracy and
  multi-display routing. Nothing else on this list covers those.
- **Doesn't cover:** physical gestures, sleep/wake.
- **Cost:** free.
- **Effort:** medium. Runner setup, a dedicated user, and an e2e test target that
  creates and cleans up its own Spaces.
- **Risk:** high while the repo is public. GitHub advises against self-hosted
  runners on public repos, because a fork's PR can run code on your machine. Only
  do this with the repo private, or with workflows restricted to your own
  branches. The tests also take over the desktop while they run.

### F. Synthetic multitouch injection: not viable

MultitouchSupport reads from the trackpad driver. There's no public or private
API to inject touch frames. The only route is a virtual HID trackpad driver
(DriverKit), which needs special entitlements and is far more work than this
project justifies. Listed so it isn't proposed again. B and C get the same
coverage for the recognizer.

### G. Structured manual checklist plus diagnostic logs

For what only a human with a trackpad can check, make it quick: add a
`TESTING-CHECKLIST.md` with numbered gesture steps per feature, and log key
events under an `os_log` subsystem (`com.grindow.app`): device attach/detach,
gesture begin/reject/emit, switch request/land/fail. You run the checklist,
then `log show --predicate 'subsystem == "com.grindow.app"' --last 10m > log.txt`,
and paste or attach the output. Claude diagnoses from the log instead of from
descriptions.

- **Covers:** #2, #3 and hot-plug, with much less of your time and much
  better evidence than "it didn't work".
- **Cost:** a few minutes of your time per change that touches hardware.
- **Effort:** small.
- **Risk:** none.

## Recommendation

Do **A + B now**, add **G** for the remaining hardware checks, and treat **C**
and **E** as later upgrades.

1. **A (CI on GitHub's macOS runners)** is the biggest gain for the least
   work. Claude gets compile and test feedback on every push, free, with no
   access to your machine. PR #4 needs this today because it has never been
   compiled.
2. **B (testable recognizer)** turns the gesture bugs, the riskiest code
   in the app, into ordinary unit tests that A runs automatically.
3. **G (checklist + logs)** handles what will always need a person (sleep/wake,
   trackpad hot-plug, macOS's own gestures) in a few minutes, with logs Claude
   can actually use.
4. Later, **C** if gesture tuning keeps changing, so tests use real finger
   timing. **E** only if Space-switching regressions keep showing up and you're
   willing to make the repo private or restrict the runner.

Skip **D** unless you want Claude running ad-hoc commands on your Mac; A covers
most of what it offers without giving shell access. **F** isn't viable.

## Order of work

1. This PR: CI (A) and the extracted recognizer with tests (B). Behavior is
   unchanged; the tests describe what the app does today.
2. PR #4, rebased on this: its four-finger fix moves into the recognizer with a
   regression test, and CI compiles and tests the whole PR.
3. PR: `os_log` events + `TESTING-CHECKLIST.md` (G).
4. Optional, later: frame recorder and fixtures (C); self-hosted e2e runner (E).
