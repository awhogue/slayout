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
swift test               # run unit tests (76+ tests)
./scripts/build-app.sh   # assemble Slayout.app (release, ad-hoc signed)
```

Requires Xcode (the standalone Command Line Tools toolchain ships neither XCTest nor Swift Testing). If `swift test` reports `no such module 'Testing'`, run:

```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

### Don't use `swift run` for real use

`swift run Slayout` works for iteration but produces an unsigned binary in `.build/...` whose path and signature change on every rebuild. macOS keys Accessibility / Input Monitoring grants to the binary signature, so each rebuild silently revokes them; some permission prompts also get attributed to `Terminal.app` (the parent process) rather than to Slayout. Use the bundled `.app` instead:

```bash
./scripts/build-app.sh
rm -rf /Applications/Slayout.app
mv Slayout.app /Applications/
open /Applications/Slayout.app
```

The bundle has a stable `CFBundleIdentifier` (`com.awhogue.slayout`) and ad-hoc signature, so permissions stick across rebuilds. Re-run `build-app.sh` after each code change to refresh the binary inside the bundle.

## First-run setup

Slayout needs **three** pieces of system permission, plus one Keyboard setting. Grant each, then quit and relaunch.

1. **Accessibility** — required to read and move other apps' windows via `AXUIElement`. Slayout will prompt and deep-link.
2. **Input Monitoring** — required for the `CGEventTap` that implements the hyper key. macOS does **not** auto-prompt for this; you have to add Slayout.app yourself: System Settings → Privacy & Security → Input Monitoring → `+` → choose `/Applications/Slayout.app`.
3. **System Settings → Keyboard → Modifier Keys → Caps Lock = "Caps Lock"** — if it's set to "No Action", `hidutil`'s caps-lock-to-F18 remap silently no-ops and the hyper key never registers.
4. **`hidutil` caps-lock remap** — Slayout invokes `hidutil property --set ...` at launch to map caps-lock to F18. No system permission needed, but the mapping is per-login-session, so Slayout reapplies it every launch.

A session-level event tap requires **both** Accessibility and Input Monitoring. If you grant only one, `tapCreate` returns nil and you'll see `FAILED to create event tap` in `~/Library/Logs/Slayout/slayout.log`.

### Conflicts with Karabiner-Elements

If Karabiner-Elements is installed, its DriverKit system extension (`org.pqrs.Karabiner-DriverKit-VirtualHIDDevice`) intercepts caps-lock at the HID layer *below* `hidutil`'s remap, so Slayout never sees the keypress. Either:

- Fully uninstall Karabiner via its own uninstaller (the dext goes with it), or
- Disable the dext in System Settings → General → Login Items & Extensions → Driver Extensions → toggle Karabiner off.

(`sudo systemextensionsctl uninstall` requires SIP off — don't do that.)

You can also sidestep the issue entirely by changing `[hyper] trigger` in your config to `right_option`, `right_cmd`, or `f19`, none of which involve `hidutil`.

## Logs

Slayout writes a definitive trace to `~/Library/Logs/Slayout/slayout.log` (and stderr). Every event-tap creation, every config reload, every recorded layout. To turn on per-key debug tracing:

```bash
launchctl setenv SLAYOUT_DEBUG 1   # then relaunch Slayout
```

Or set `SLAYOUT_DEBUG=1` in the shell before launching directly.

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
