# Grindow Glossary

Shared vocabulary for Grindow. Code and docs should use these terms consistently.
Everything below is either a **space** (a macOS primitive) or a **Grindow UI wrapper**
around one.

| Term | Definition |
|---|---|
| **Space** | The macOS-internal unit: one virtual screen the WindowServer manages, identified by a CGS managed-space ID (the `UInt64` used throughout the code, `SpaceInfo.id`). Every desktop and every full-screen app is a space underneath. This is the raw system primitive. CGS `type`: `0` = desktop, `4` = full-screen. |
| **Desktop** | A **regular space** (CGS `type 0`): wallpaper-backed, holds many app windows. What Mission Control's top strip labels "Desktop 1, 2, …". Belongs to one display. |
| **Full-screen app** | A **space macOS auto-creates** (CGS `type 4`) when one app is taken full-screen (green button). Holds exactly one app, no wallpaper, no other windows; disappears when full-screen is exited. |
| **App** | A running application (Brave, Xcode). Has many **windows**, can span multiple **desktops**, and can also be full-screen (its own space). |
| **Window** | A single window of an app. Lives on a **desktop**; can be moved between desktops; taking it full-screen converts it into a **full-screen app** space. |
| **Cell** | A **Grindow UI** slot in the grid mapped to one **space**. Clicking it switches to that space. An "empty cell" has no space assigned. |
| **Grid** | Grindow's 2-D arrangement of **cells** (rows × columns) laying out spaces spatially. |

## Notes

- Grindow switches spaces with the private `CGSManagedDisplaySetCurrentSpace` SPI —
  an instant switch that bypasses the WindowServer's normal space transition (hence
  no animation, and some redraw quirks under investigation).
- Grindow only **detects** trackpad gestures; macOS still acts on its own three-finger
  gestures unless they're disabled in System Settings → Trackpad → More Gestures.
- Only spaces on **currently-connected displays** are shown; macOS retains space
  arrangements for previously-attached monitors ("ghost" displays), which are filtered out.
