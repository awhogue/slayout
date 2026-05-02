# Slayout — keyboard-driven macOS window manager

## Context

The user currently runs Karabiner-Elements (for a hyper-key macro: caps-lock → ⌘⌥⌃⇧) plus Slate (for hyper-keyed app launches and window arrangement). Slate is unmaintained and missing features the user wants. Slayout will be a single native macOS app that supersedes both, plus adds two new capabilities:

1. **Record-and-bind layouts** — capture the current window arrangement and bind it to a hyper-key for one-press restore.
2. **Last-layout restore** — automatically snapshot the window arrangement right before a display reconfiguration (e.g. sleep/wake on a laptop with an external monitor) so a single keystroke puts windows back where they belong.

Spaces support is explicitly deferred to v2.

## Decisions (from clarifying Qs)

- Slayout fully replaces Karabiner — it implements the hyper modifier itself via a CGEventTap.
- Configuration is a plain-text TOML file (no GUI prefs in v1).
- Layout recording is a two-step "press save, then press a key to bind" flow.
- "Last layout" is captured on `NSApplication.didChangeScreenParametersNotification`.
- Windows are matched on restore by `bundleID + title` with a prefix fallback, then "first window of that app".
- Distribution target: personal local build, ad-hoc signed.
- Spaces: deferred to v2.

## Testing approach (TDD, v1)

This is built test-first. Every module ships with unit tests in v1; OS calls are isolated behind protocols so the pure logic is testable without a running window server.

Seams (protocols) to introduce so logic is unit-testable:

- `WindowServer` — abstracts AX: `frontmostWindow()`, `allWindows()`, `setFrame(_:on:)`, `focus(bundleID:)`. Real impl wraps `AXUIElement`; tests use an in-memory fake.
- `ScreenProvider` — abstracts `NSScreen.screens` to a list of `(displayID, name, frame, visibleFrame)`.
- `EventSource` — abstracts the CGEventTap; tests inject synthetic key events into `Bindings.dispatch`.
- `Clock` — for the "stable for ≥ 5 s" rule in `LastLayoutWatcher`.
- `FileStore` — read/write `config.toml` and `layouts.toml` (so tests use temp dirs).

Pure logic that gets direct unit tests (no fakes needed beyond inputs):

- TOML config parsing → typed `Config` struct (valid + malformed inputs).
- Frame math: `Actions.frame(for: .leftTwoThirds, in: visibleFrame)` etc.
- Window-match algorithm (exact title → prefix → first-of-app, with claimed-window tracking).
- Screen fingerprint matching (same displays / subset / different).
- Recorder state machine (Idle → Recording → Bound; abort paths).
- Last-layout selector (which snapshot to restore given current screens).

XCTest targets in `Tests/SlayoutTests/`. Keep AX-touching code in a thin `WindowServerAX` adapter that is exercised only via a small integration test (skipped in CI, runnable locally with Accessibility granted).

## High-level architecture

Single Swift app, AppKit menu-bar (LSUIElement) shell. Modules:

| Module | Responsibility | Key APIs |
|---|---|---|
| `HyperKey` | Watch a chosen trigger key, treat it as the hyper modifier, dispatch the next keydown to the binding system, swallow the event | `CGEvent.tapCreate`, `CGEventTapProxy` |
| `Bindings` | Map `(hyper, key)` → action; hot-reload from config | TOML parser |
| `WindowEngine` | Enumerate, focus, move, resize windows on the frontmost or any app | `AXUIElement`, `AXUIElementCopyAttributeValue`, kAXPositionAttribute, kAXSizeAttribute |
| `ScreenGeometry` | Compute frames for half/third/two-thirds/full on any `NSScreen`; resolve "external" / "builtin" / display index | `NSScreen.screens`, `NSScreen.frame`/`visibleFrame` |
| `LayoutStore` | Persist named layouts to JSON; capture/restore | `CGWindowListCopyWindowInfo` + AX |
| `LastLayoutWatcher` | Snapshot before/after screen-param changes; expose "restore last" action | `NSApplication.didChangeScreenParametersNotification` |
| `Recorder` | Two-step record-then-bind state machine; menubar status feedback | — |
| `MenubarUI` | Status item, "Reload config", "Bindings…", "Quit" | `NSStatusBar` |

## Permissions

On first run, prompt for and verify:
- **Accessibility** (`AXIsProcessTrustedWithOptions`) — required for `AXUIElement` window control.
- **Input Monitoring** — required for the `CGEventTap` that implements hyper.

Show a setup window with deep-links to System Settings panels if either is missing.

## Hyper-key implementation

- Read `[hyper] trigger` from config (default: `caps_lock`; alternatives: `right_cmd`, `right_option`, `f19`).
- Install a `CGEventTap` at `kCGSessionEventTap`, listening for `keyDown`, `keyUp`, `flagsChanged`.
- While the trigger is held, intercept the next `keyDown`, look up the binding, run it, and **return nil from the tap callback** to swallow the event (so the underlying app never sees the keypress).
- If no binding matches, pass the event through unchanged.
- Caps-lock requires special handling: macOS toggles caps-lock state in the HID layer. Use the standard trick of remapping caps-lock at the IOKit HID level via `hidutil property --set '{"UserKeyMapping":...}'` invoked once at launch, mapping caps-lock to F18; then bind hyper to F18-held.

## Config file

Location: `~/.config/slayout/config.toml` (created on first run with sensible defaults).

```toml
[hyper]
trigger = "caps_lock"   # caps_lock | right_cmd | right_option | f19

[apps]
# hyper+<key> = bundle id or app name
T = "Terminal"
C = "Google Chrome"
E = "Emacs"

[window]
# hyper+<key> = built-in window action
"return" = "fullscreen"
"["      = "left-two-thirds"
"]"      = "right-two-thirds"
"h"      = "left-half"
"l"      = "right-half"
"up"     = "screen:external"
"down"   = "screen:builtin"

[meta]
record = "s"     # enter "save layout" mode
restore_last = "z"   # restore last-layout-before-display-change
reload = "r"     # reload config
```

User-recorded layouts are appended automatically to a separate file (`~/.config/slayout/layouts.toml`) so they survive config edits without merge conflicts.

## Built-in window actions

Computed against `NSScreen.visibleFrame` of the screen the active window is on (or the target screen for `screen:*` actions):

- `fullscreen` (visibleFrame, not native macOS fullscreen which creates a new space)
- `left-half`, `right-half`, `top-half`, `bottom-half`
- `left-two-thirds`, `right-two-thirds`, `left-third`, `middle-third`, `right-third`
- `center` (preserve size, center in screen)
- `screen:<name>` — move to display matching name (`external`, `builtin`, or index `0`/`1`)
- `nudge:left|right|up|down:<px>` (optional, low priority)

## Record-and-bind UX

State machine in `Recorder`:

1. Idle → user presses **hyper+s**.
2. Menubar icon turns red, NSStatusItem title shows `● REC — press a key`.
3. Next `(hyper, key)` event:
   - If the key is already bound to a non-layout action, beep + abort with a brief notification.
   - Otherwise: capture `LayoutSnapshot { windows: [WindowState], screens: [ScreenFingerprint], capturedAt }` and write it to `layouts.toml` keyed by that key.
4. Subsequent presses of `hyper+<key>` invoke `restore(layoutForKey)`.

`WindowState`:
```swift
struct WindowState {
    let bundleID: String
    let appName: String
    let title: String
    let screenIndex: Int    // index into snapshot.screens
    let frame: CGRect       // in that screen's local coords
}
```

`ScreenFingerprint` records each display's display ID, name, and frame so restore can map by display ID first, then by index, then by "primary".

Restore algorithm:
1. For each `WindowState`, find the matching live window:
   - Same `bundleID` + exact `title` → use it.
   - Else same `bundleID` + title prefix match → use it.
   - Else first window of that bundleID that hasn't been claimed yet.
2. Resolve target screen via `ScreenFingerprint`.
3. Set position then size via AX.

## Last-layout (wake-from-sleep) restore

- On launch and on every `NSApplication.didChangeScreenParametersNotification`:
  - Capture a snapshot **before** applying any restore logic.
  - Keep two snapshots in memory and on disk: `last-stable.json` (the most recent snapshot taken when the screen config was unchanged for ≥ 5 s) and `pre-change.json` (the snapshot captured when a screen-change notification fires).
- `hyper+z` (configurable) restores `pre-change.json` if the current screen config matches its `screens` fingerprint; otherwise restores `last-stable.json`.
- This specifically fixes the laptop+external-monitor wake bug: when macOS forgets the external monitor and then rediscovers it, `pre-change.json` was taken with both displays attached, so windows go back.

## Critical files (to be created)

- `Package.swift` or `Slayout.xcodeproj/` — build configuration (Swift Package executable target is simplest; produces a `.app` via a small Xcode wrapper for the LSUIElement bundle plist).
- `Sources/Slayout/AppDelegate.swift` — bootstrap, permissions check, menubar.
- `Sources/Slayout/HyperKey/EventTap.swift` — CGEventTap install + hyper detection.
- `Sources/Slayout/HyperKey/CapsLockRemap.swift` — `hidutil` invocation.
- `Sources/Slayout/Bindings/Config.swift` — TOML load + watch.
- `Sources/Slayout/WindowEngine/AXWindow.swift` — AX wrappers.
- `Sources/Slayout/WindowEngine/Actions.swift` — built-in actions (halves/thirds/screens).
- `Sources/Slayout/Layouts/LayoutStore.swift` — capture/restore + matching.
- `Sources/Slayout/Layouts/LastLayoutWatcher.swift` — screen-param observer.
- `Sources/Slayout/Recorder/Recorder.swift` — state machine.
- `Sources/Slayout/MenubarUI/StatusItem.swift` — menubar.
- `Sources/Slayout/Platform/WindowServer.swift` — protocol + AX impl.
- `Sources/Slayout/Platform/ScreenProvider.swift` — protocol + NSScreen impl.
- `Sources/Slayout/Platform/EventSource.swift` — protocol + CGEventTap impl.
- `Tests/SlayoutTests/ConfigTests.swift`
- `Tests/SlayoutTests/ActionsFrameMathTests.swift`
- `Tests/SlayoutTests/WindowMatchTests.swift`
- `Tests/SlayoutTests/RecorderTests.swift`
- `Tests/SlayoutTests/LastLayoutSelectorTests.swift`
- `Tests/SlayoutTests/BindingsDispatchTests.swift`
- `Tests/SlayoutTests/Fakes/FakeWindowServer.swift`
- `Tests/SlayoutTests/Fakes/FakeScreenProvider.swift`
- `Tests/SlayoutTests/Fakes/FakeClock.swift`
- `Resources/default-config.toml` — seed on first run.
- `README.md` — install + permission setup.
- `design-doc.md` — copy of this design doc kept in the repo and updated as the design evolves.
- `CLAUDE.md` — repo-level instructions for future Claude sessions (build/test commands, key invariants like "TDD, isolate OS calls behind protocols", pointers to `design-doc.md`, current-state notes). Created in step 1 and updated as each module lands.

External dep: a TOML parser. Recommended `TOMLKit` (SwiftPM-friendly).

## Build order (test-first at every step)

Each step: write the failing test first against the protocol/pure-logic seam, then implement, then wire to the real OS adapter.

1. Project skeleton: SwiftPM executable + test target, LSUIElement Info.plist, menubar status item, permissions check (AX + Input Monitoring) with deep-links to System Settings. Also create `design-doc.md` (copy of this plan) and `CLAUDE.md` (build/test commands, TDD invariant, pointer to `design-doc.md`). Both files are updated incrementally as each subsequent step lands.
2. `Config` TOML parsing — tests first (valid, malformed, defaults), then implementation with `TOMLKit`.
3. `ScreenProvider` protocol + `Actions` frame math — tests for halves/thirds/two-thirds/center/screen-resolve against fake screens.
4. `WindowServer` protocol + `FakeWindowServer` — tests for `Actions.apply(...)` end-to-end on the fake.
5. AX adapter (`WindowServerAX`) — small live integration test; validate with hardcoded `Cmd+Opt+Ctrl+Shift+H` shortcut → left-half before hyper exists.
6. `EventSource` protocol + `Bindings.dispatch` — unit tests inject synthetic key events; then real `CGEventTap` adapter + caps-lock-to-F18 `hidutil` remap.
7. `LayoutStore` capture/restore — tests cover the matching algorithm (exact / prefix / first-of-app, claimed-window tracking, screen-fingerprint resolution).
8. `Recorder` state machine — pure unit tests on Idle→Recording→Bound and abort paths; then wire to menubar status feedback.
9. `LastLayoutWatcher` selector — pure unit tests using `FakeClock` and synthetic screen-change events; then real `NSApplication.didChangeScreenParametersNotification` observer + `restore_last` action.
10. Polish: live config reload on file change, error notifications, README with install + permission setup.
11. Document v2 backlog: Spaces, GUI prefs, named layouts UI.

## Verification

Automated (run on every change):

- `swift test` — all unit tests in `Tests/SlayoutTests/` must pass. Includes config parsing, frame math, window matching, recorder state machine, last-layout selection, and bindings dispatch via fakes.

Manual end-to-end checks (the OS-integration seams that fakes cannot cover):

- **Permissions**: launch on a clean machine; verify the setup flow links into System Settings and detects re-grant.
- **Hyper**: with `trigger = caps_lock`, hold caps-lock + T → Terminal focuses; tap caps-lock alone → no action and no caps-lock toggle. Confirm the keydown is swallowed (target app shows no `t` insertion).
- **Built-in actions**: open Safari, hyper+`[` → window snaps to left two-thirds of current screen; hyper+up → moves to external display; hyper+return → fills visibleFrame.
- **Record/restore**: arrange 3 apps; hyper+s, hyper+1 → confirms via menubar; rearrange; hyper+1 → restores.
- **Last-layout**: arrange windows on laptop+external; close laptop lid (or unplug+replug external) so macOS forgets the external; hyper+z → windows go back to the external once it reappears.
- **Title matching**: open two Chrome windows with different titles; record; rename one tab; restore — both still land on the right frames thanks to prefix-match.
- **Config reload**: edit `config.toml`, save; menubar shows "config reloaded"; new binding works without restart.

## Out of scope (v2+)

- Spaces awareness: `move-to-space`, multi-space layout capture/restore (will need private SkyLight/CGS APIs — `CGSCopySpaces`, `CGSMoveWindowsToManagedSpace`).
- GUI preferences window.
- Named layouts (rather than single-key-bound).
- Per-app rules (e.g. "Slack always on external").
- Window focus cycling within an app.
