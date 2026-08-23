# Grindow — Status (2026-07-02)

Snapshot of what works, what's in progress, and what still needs testing on the
`claude/multitouch-rewrite` branch. See [GLOSSARY.md](GLOSSARY.md) for the exact
meaning of *space / desktop / full-screen app / app / window / cell / grid*.

## Working / validated at runtime

- **Three-finger swipe detection** for all four directions (up/down/left/right).
- **Direct space switching** via `CGSManagedDisplaySetCurrentSpace` on the
  **main display** (verified: 3-finger swipes and popover clicks both switch).
- **Startup race fixed** — the grid no longer initializes empty and no longer
  persists an empty layout (commit `bb708e6`).
- **Ghost-display filtering** — spaces from previously-attached but currently
  disconnected monitors are excluded (commit `bb708e6`).

## Changed in this commit (needs a test pass)

- **Removed the stale Accessibility permission UI/prompt.** Grindow doesn't need
  Accessibility (MultitouchSupport + direct CGS switching don't require it).
  → *Test:* Settings no longer shows an "Accessibility" section; no permission
  prompt appears at launch. `AccessibilityHelper.swift` is now unused (left in the
  project; safe to delete later).
- **Grid auto-updates** via a single `syncGridToSystem()` called on every space
  change and whenever the menu-bar popover opens — no manual "Refresh" needed.
  → *Test:* add/remove/rename a desktop, then open the popover; it should reflect
  reality immediately. (Adding a desktop without switching may only refresh on the
  next popover-open, since macOS posts no add/remove notification.)
- **Mini-grid cell labels** now show a distinguishable short label (number, `⤢N`
  for full-screen, or the start of a custom name) instead of every desktop reading
  "Des".
  → *Test:* cells in the popover are individually identifiable.
- **GLOSSARY.md** added.

## Known NOT working / open

- **Multi-monitor is the core problem (highest priority).** The user runs **3
  displays**; the grid flattens spaces from all displays into one flat list, but on
  macOS **each display has its own independent active space**, and our position
  tracking uses `CGSGetActiveSpace` (main display only). This is very likely the
  root cause of the next item.
- **"Desktop 1" (and some cells) won't switch; swiping to/from them gets stuck.**
  Under active investigation. Desktop 1 = space `id=3`, type 0, main display.
  Diagnostics for this are **committed but commented out** in `SpaceManager.swift`
  (a `/tmp` file-logger + roster dump + switch CALL/RESULT). To re-enable, uncomment
  the `gdiag` helper, the `diagLastRoster` property, and the `// DIAG:` blocks in
  `refreshSpaces()` / `switchToSpace(id:)`. Repro to capture: open popover, click
  "Desktop 1", read `/tmp/grindow-gesture.log`.
- **Full-screen / minimize breaks.** Taking a window full-screen tries then snaps
  back; minimizing lands the window in front of a full-screen space instead of a
  regular desktop. Not yet investigated; may be tied to multi-monitor / direct
  switching.
- **Window redraw ghosting.** Brave's vertical-tab sidebar persists on screen after
  switching spaces until another app is selected from the Dock. Likely the direct
  CGS switch skips the WindowServer occlusion/redraw the normal transition performs.
- **No switch animation** (requested). The direct CGS switch is intentionally
  instant; animating needs a different mechanism or a drawn overlay.
- **Cannot create new (non-full-screen) desktops** yet (requested).

## Environment notes

- **macOS's own three-finger gestures must be OFF** (System Settings → Trackpad →
  More Gestures: Mission Control, App Exposé, Swipe between full-screen apps) or they
  fight Grindow. Grindow only *detects* gestures; it does not suppress macOS's.
- Debugging: **NSLog does not reliably reach the unified log** for this app — use a
  file logger (`/tmp/...`). The shell aliases `log`, so call `/usr/bin/log`.
