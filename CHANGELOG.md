# Changelog

## 0.2.1 — Electron app fix

### Fixes

- **Electron apps now respond to window actions.** Apps like Claude and Granola don't enable their own AX subsystem on launch, so `AXFocusedWindow` / `AXWindows` queries against them returned `apiDisabled` (-25211) and Slayout silently did nothing. When that error comes back, Slayout now writes `AXManualAccessibility = true` to the app's AX element and retries — the same trick Rectangle and Loop use. PIDs are cached so the attribute is only set once per process lifetime.

### Install

```bash
unzip Slayout-0.2.1.zip -d /Applications/
open /Applications/Slayout.app
```

In-place upgrade from 0.2.0: replace the bundle. Config and saved layouts are untouched.

---

## 0.2.0 — resilience & polish

A small follow-up release focused on diagnostics and "things that should just work."

### New

- **`middle-two-thirds` window action.** Centered 2/3-wide tile. Bind with e.g. `"\\" = "middle-two-thirds"` (a.k.a. `hyper+|`).
- **Shifted-symbol key aliases.** Config keys like `"|"`, `"?"`, `":"`, `"<"`, `"+"`, `"!"`–`")"` are auto-mapped to their unshifted equivalents (`\`, `/`, `;`, `,`, `=`, digits) so bindings written the obvious way actually fire.
- **Verbose Logging toggle in the menubar.** New menu items: `Verbose Logging` (persisted across launches), `Open Log File…`, `Reveal Log in Finder`, `Open Config…`. When verbose is on, every hyper-key press, `setFrame`, focus call, and AX failure is traced — handy for diagnosing why a particular app isn't responding.
- **Resilient config parsing.** A single bad line (unknown action, wrong type) is now skipped with a warning instead of nuking the whole config. After reload, a popup lists the skipped lines with an "Open Config" button. Only TOML-level syntax errors fall back to defaults.

### Fixes

- **App lookup is fuzzier.** `Z = "Zoom"` now finds `/Applications/zoom.us.app` (whose internal `CFBundleName` is "zoom.us"). The scan does exact → prefix → substring matching across filename, `CFBundleName`, `CFBundleDisplayName`, and `CFBundleExecutable`, picking the shortest (most specific) candidate. Bundle IDs still pass straight through.
- **AX error reporting.** `frontmostWindow` and `setFrame` now log named AX errors (`cannotComplete`, `apiDisabled`, `notImplemented`, …) when things go sideways, so it's possible to diagnose apps that refuse to respond to resize.
- **`activate(options: [.activateAllWindows])`** when focusing a running app, which helps with some apps that previously refused to come forward.

### Internals

- **82 unit tests** (up from 76), still all green. New coverage: middle-two-thirds frame math, resilient parse with warnings, shifted-symbol key normalization.

### Install

Download `Slayout-0.2.0.zip`, then:

```bash
unzip Slayout-0.2.0.zip -d /Applications/
# Right-click /Applications/Slayout.app → Open (first time only — Gatekeeper bypass)
open /Applications/Slayout.app
```

Upgrade from 0.1.0: just replace the bundle. Config and saved layouts are untouched.

---

## 0.1.0 — first release

A keyboard-driven macOS window manager that supersedes Karabiner-Elements + Slate with one tool.

### What's in the box

- **Hyper-key, no Karabiner.** Slayout remaps caps-lock → F18 via `hidutil` and installs its own `CGEventTap`. Other modifier triggers are supported too (`right_option`, `right_cmd`, `f19`).
- **App focus shortcuts.** `hyper+t → Terminal`, `hyper+c → Chrome`, etc. Names or bundle IDs in TOML.
- **Window tiling.** `fullscreen`, halves, thirds, two-thirds, center, plus `screen:builtin` / `screen:external` to throw windows between displays. Built-in layouts compute against `visibleFrame` so menubar and Dock are respected. (Top-left global coordinates internally — matches AX / `CGWindowList`.)
- **Record-and-bind layouts.** `hyper+s` then any key → captures every regular-app window's position and binds it to that key. Press the key later to restore. Saved as JSON under `~/.config/slayout/layouts/`.
- **Last-layout restore.** `hyper+z` puts windows back to the last stable arrangement for the *current* display configuration. Designed to fix the "macOS forgot the external monitor after wake" problem — windows go where they belong as soon as the external comes back. Per-fingerprint stable layouts mean laptop-only and laptop+external states are remembered independently.
- **Live config reload.** Edit `~/.config/slayout/config.toml`; Slayout watches the file and reloads on save. `hyper+r` does the same explicitly.
- **Menubar status.** Tiny "SL/AY" template icon that auto-tints for light/dark menubar; shows `● ` while in record mode.
- **Logs.** `~/Library/Logs/Slayout/slayout.log` always has a definitive trace. Set `SLAYOUT_DEBUG=1` for per-keystroke detail.

### Architecture

- `SlayoutCore` is a pure-Swift library; OS calls live behind protocols (`WindowServer`, `ScreenProvider`, `EventSource`, `Clock`) so dispatch logic, frame math, layout matching, and the recorder state machine are all unit-testable.
- `Slayout` is a thin AppKit `LSUIElement` executable that wires the core to the real `AXUIElement` / `NSScreen` / `CGEventTap` adapters.
- **76 unit tests** across 12 suites (`swift test`). The OS-touching adapters are exercised manually.

### Install

Download `Slayout-0.1.0.zip` (≈840 KB), then:

```bash
unzip Slayout-0.1.0.zip -d /Applications/
# Right-click /Applications/Slayout.app → Open (first time only — Gatekeeper bypass)
open /Applications/Slayout.app
```

On first launch, grant **Accessibility** when prompted (System Settings → Privacy & Security → Accessibility). On macOS Sequoia / Tahoe that's all you need; older macOS may also need Input Monitoring.

### Heads-ups

- **Set System Settings → Keyboard → Modifier Keys → Caps Lock = "Caps Lock"**, not "No Action". With "No Action" macOS overrides `hidutil`'s remap and the hyper key never fires.
- **Karabiner-Elements conflicts** with caps-lock as the trigger. Either fully uninstall Karabiner (its DriverKit dext goes with it) or disable the dext via System Settings → General → Login Items & Extensions → Driver Extensions. Or set `[hyper] trigger = "right_option"` and sidestep entirely.
- **Spaces support is deferred to v2.** Layouts capture window position on a single screen; Mission Control spaces are not recorded or restored.
- The bundle is **ad-hoc signed**, not Developer-ID-signed or notarized. Fine for personal use across your own machines; not suitable for wider distribution.

### Roadmap (v2)

- Spaces awareness (move-to-space, multi-space layout capture/restore)
- Per-app rules (e.g. "Slack always on external display")
- Ignore-list for layout capture (skip Activity Monitor / Finder by default)
- GUI preferences window
- Auto-launch at login built in (currently a manual System Settings step)
