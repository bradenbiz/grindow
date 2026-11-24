# Testing in the macOS VM (no Mac needed)

Agents can build, install, run and click through Grindow in a real macOS 26 desktop
without Braden's MacBook. The VM runs on **Lisbon** (Omarchy, i5-9400) in rootless
Docker using [macbox](https://github.com/0xdaniell/macbox), which boots macOS under
QEMU/KVM with a paravirtual GPU.

Set up November 23, 2026. The VM is macOS 26.7.3 (25G342), x86_64, admin user `dev`.
Its password is in 1Password as `op://Agents/macbox-lisbon-dev/password`. You rarely
need it: sudo is passwordless and the VM logs in automatically.

## What it covers

| Check | VM | Still needs the real Mac |
|---|---|---|
| App launches, onboarding, menu bar popover, Settings, HUD rendering | yes | |
| Accessibility grant and its survival across rebuilds | yes (granted once; CI builds are re-signed with a stable identity) | |
| Space switching through Grindow (synthetic Dock swipes, bursts, both directions) | yes, verified: grid clicks 2 → 6 and 6 → 1 | |
| Reading Space state from a script | yes: `grindow-vm spaces` | |
| Everything after gesture recognition: swipe bursts, reversals, edge behavior, inversion, the swipe HUD | yes, with fake swipes (`grindow-vm swipe`, Debug builds only) | |
| `swift test`, native C tests | yes (Command Line Tools, Swift 6.3.3), and CI | |
| Full Xcode build (`xcodebuild`) | CI only. Xcode needs an Apple Account download | |
| Real trackpad gestures (MultitouchSupport and the recognizer) | no trackpad in a VM, so Grindow shows "Inactive" | recordings (TESTING-OPTIONS C) and replay tests |
| Sleep/wake, hot-plug, multiple physical displays | no | yes |
| macOS 27 | no: macOS for Intel ends at 26 | yes |

## Daily use

`Scripts/vm/grindow-vm` works from Malta, Lisbon, or any tailnet machine with `gh`
and `tailscale`:

```sh
Scripts/vm/grindow-vm status            # is the VM up?
Scripts/vm/grindow-vm up                # start it (about 1 min to the desktop)

git push                                # CI builds a universal Grindow.app artifact
Scripts/vm/grindow-vm install           # newest green CI run of this branch → VM, re-signed, launched
Scripts/vm/grindow-vm install --pr 4    # or a PR, or --run <id>

Scripts/vm/grindow-vm spaces            # 8B9D…: 1 2 [3] 4 5 6   ([n] is active)
Scripts/vm/grindow-vm shot vm.png       # screenshot (1440x900), then look at it
Scripts/vm/grindow-vm click 1144 14     # Grindow's menu bar icon
Scripts/vm/grindow-vm switch right 2    # macOS's own Ctrl-→ switch, for comparison
Scripts/vm/grindow-vm swipe right 2     # two fake three-finger swipes, then spaces
Scripts/vm/grindow-vm log 10            # Grindow's log lines, last 10 minutes
Scripts/vm/grindow-vm sh 'pgrep -l Grindow'

Scripts/vm/grindow-vm down              # stop it when done: it holds 6 of Lisbon's 12 GB of RAM
```

Clicks use the guest's pixels, which equal screenshot pixels at 1440x900. Take a
screenshot after every click to confirm it did what you meant. `find`,
`click-text` and `wait-text` locate on-screen text with OCR.

A Space-switch test, end to end:

```sh
Scripts/vm/grindow-vm install --pr 4
Scripts/vm/grindow-vm spaces                      # note the active Space
Scripts/vm/grindow-vm click 1144 14               # open the popover
Scripts/vm/grindow-vm shot grid.png               # find the destination cell
Scripts/vm/grindow-vm click <x> <y>               # click it
sleep 3; Scripts/vm/grindow-vm spaces             # did the right Space become active?
```

## Fake swipes

The VM has no trackpad, so Debug builds of Grindow (CI's artifact is one) accept
fake swipes instead. `GestureInterceptor` listens for the distributed notification
`com.grindow.debug.swipe` with `userInfo["direction"]` set to `up`, `down`, `left`
or `right`, and treats each one as a three-finger swipe the recognizer just saw.
Everything after that is the real code path: "Invert swipe direction", grid
navigation, edge behavior, bursts and the swipe HUD. Only the gesture event tap and
`ThreeFingerSwipeRecognizer` are skipped; the recognizer has its own unit tests.
Release builds don't contain the listener.

```sh
Scripts/vm/grindow-vm swipe down                      # one swipe, wait 2 s, print spaces
Scripts/vm/grindow-vm swipe right 3 --interval 120    # a rapid burst of three
Scripts/vm/grindow-vm swipe right,left 2              # right right left left: a reversal mid-burst
```

`swipe` copies `Scripts/vm/swipe.swift` into the VM and compiles it when it has
changed, so a burst isn't slowed by `swift` startup. `--interval` is the gap
between swipes in milliseconds (default 300); `--settle` is how long to wait
before printing spaces (default 2 seconds).

`grindow-vm log 1` shows what Grindow did with each swipe, real or fake, under the
`swipe` category: `debug swipe right received`, then the grid move
(`swipe right: 1,2 -> 0,2`), `at the edge (stop)`, or why it was refused.

Settings can be changed from the command line; restart Grindow after writing them:

```sh
Scripts/vm/grindow-vm sh 'defaults write com.grindow.app edgeBehavior wrap'   # stop | wrap | bounce
Scripts/vm/grindow-vm sh 'defaults write com.grindow.app invertSwipes -bool true'
Scripts/vm/grindow-vm restart
```

Directions are finger directions, before "Invert all swipe directions", which is
**on by default**: then `up` moves down the grid and `right` moves left. With the
default 2x3 grid, Spaces 1 2 3 are the top row and 4 5 6 the bottom row, so with
default settings `up` from 2 goes to 5 and `left` from 3 stops at the edge. The log
line shows the direction after inversion. Turn inversion off (below) if you'd
rather have `right` mean right.

The HUD stays up for about a second and the bounce for half a second, and
`grindow-vm shot` takes most of that, so a screenshot taken after `swipe` returns
misses them. Take it from Lisbon while the swipe is posted:

```sh
tailscale ssh bradenbiz@lisbon 'bash -lc "ssh macbox \"~/.grindow-vm/swipe up 1 0\" & sleep 0.25;
  ~/repos/macbox/macbox screenshot /tmp/hud.png >/dev/null; wait; cat /tmp/hud.png"' > hud.png
```

## Gotchas

- **Click-to-show-desktop is off.** A click on the wallpaper used to hide all
  windows, which Dock reports like Mission Control, so Grindow refused to navigate
  ("Close Mission Control or App Exposé…"). Turned off with
  `defaults write com.apple.WindowManager EnableStandardClickToShowDesktop -bool false`.
- Grindow keeps showing its last error in the popover until a navigation
  succeeds, even after the cause is gone.
- On macOS 26.7.3 an ordinary desktop has one full-screen Dock window at layer 20
  and none at layer 18 (seen with `CGWindowListCopyWindowInfo`). The macOS 27
  branch of `strafe_is_expose_active` treats any layer-20 Dock window as Mission
  Control. If 27 keeps that window, the branch would block every navigation.
  Untested; this VM can't run 27.
- The VM has six desktops on one display. Don't remove them; tests assume a grid.
- Screenshots in Recovery and OpenCore are 1280x800 while clicks stay 1440x900
  (multiply by 1.125). Only relevant if you reinstall.

## Recovering

- VM wedged: `Scripts/vm/grindow-vm down && Scripts/vm/grindow-vm up`.
- Signing or Spaces setup lost: `Scripts/vm/grindow-vm setup` (safe to run again).
- Accessibility lost (e.g. a different signing identity): System Settings → Privacy &
  Security → Accessibility → Grindow on. It asks for the password; type it with
  `op run` piping `$VMPW` into `macbox type -` on Lisbon. Never put it in a command line.
- Back to the state from November 23 (desktop, 6 Spaces, CLT, identity, grant):
  on Lisbon, `macbox down`, copy `/data/macbox-backups/grindow-ready/*` over
  `~/.local/share/macbox/home/.local/share/reims-ctl/vms/mac/`, `macbox up`.

How Lisbon's host side was set up (rootless Docker without sudo, macbox's paths)
is in fleet's `lisbon-macos-vm.md`.
