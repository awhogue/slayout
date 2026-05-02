# Slayout

Keyboard-driven macOS window manager. Replaces Karabiner-Elements + Slate with a single tool that handles the hyper-key, app-launching shortcuts, window arrangement, and per-keystroke layout recording.

## Features

- Caps-lock-as-hyper, no Karabiner needed (uses `hidutil` to remap caps-lock → F18 internally).
- TOML-configured bindings for app focus (`hyper+T → Terminal`) and window actions (`hyper+[ → left two-thirds`, `hyper+up → external display`, etc.).
- **Record-and-bind layouts**: `hyper+S` then any key → captures the current window arrangement and binds it to that key for one-press restore.
- **Last-layout restore**: `hyper+Z` puts windows back where they were the last time the current display configuration was stable. Designed to fix the "macOS forgot the external monitor after wake" problem.

Spaces support is deferred to v2.

## Build

```bash
swift build              # debug build
swift run Slayout        # run from terminal
swift test               # run unit tests (76+ tests)
```

Requires Xcode 16+ (the standalone Command Line Tools toolchain ships neither XCTest nor Swift Testing). If `swift test` reports `no such module 'Testing'`, run:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

## First-run setup

Slayout needs three pieces of system permission. The app will prompt you and deep-link to System Settings; grant each, then quit and relaunch.

1. **Accessibility** — required to read and move other apps' windows via `AXUIElement`.
2. **Input Monitoring** — required for the `CGEventTap` that implements the hyper key.
3. **`hidutil` caps-lock remap** — Slayout invokes `hidutil property --set ...` at launch to map caps-lock to F18. Requires no special permission, but is per-login-session: re-run on every login (Slayout does this automatically when launched at login).

## Configuration

`~/.config/slayout/config.toml` is created on first launch with sensible defaults:

```toml
[hyper]
trigger = "caps_lock"   # caps_lock | right_cmd | right_option | f19

[apps]
# Hyper + key = focus this app
T = "Terminal"
C = "Google Chrome"

[window]
# Hyper + key = built-in window action
"return" = "fullscreen"
"[" = "left-two-thirds"
"]" = "right-two-thirds"
"h" = "left-half"
"l" = "right-half"
"k" = "top-half"
"j" = "bottom-half"
"up" = "screen:external"
"down" = "screen:builtin"

[meta]
record = "s"           # hyper+s, then a key, to record-and-bind a layout
restore_last = "z"     # hyper+z to restore the last stable layout for the current displays
reload = "r"           # hyper+r to reload the config file
```

Saved layouts live in `~/.config/slayout/layouts/<key>.json`. Edit the TOML file freely — Slayout watches it and reloads on save.

### Built-in window actions

`fullscreen`, `left-half`, `right-half`, `top-half`, `bottom-half`, `left-two-thirds`, `right-two-thirds`, `left-third`, `middle-third`, `right-third`, `center`, `screen:builtin`, `screen:external`, `screen:0`, `screen:1`, …

## Architecture

See [`design-doc.md`](design-doc.md) for the full design. TL;DR:

- `SlayoutCore` is a pure-Swift library; OS calls live behind protocols (`WindowServer`, `ScreenProvider`, `EventSource`) so dispatch logic, frame math, layout matching, and the recorder state machine are all unit-tested without a window server.
- `Slayout` is a thin AppKit menubar executable that wires the core to the real `AXUIElement` / `NSScreen` / `CGEventTap` adapters.

## Status

v1 (current): hyper-key, app/window bindings, record-and-bind layouts, last-layout restore on display change.
v2 (planned): MacOS Spaces support, GUI preferences, per-app rules.

## License

MIT — see [`LICENSE`](LICENSE).
