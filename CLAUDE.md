# Slayout — Claude session notes

Slayout is a keyboard-driven macOS window manager that supersedes Karabiner-Elements + Slate.
The full design is in `design-doc.md` — read it before making changes.

## Hard invariants

- **TDD is mandatory.** Write a failing test before the implementation. Every module ships with unit tests in v1.
- **OS calls live behind protocols.** `WindowServer`, `ScreenProvider`, `EventSource`, `Clock`, `FileStore`. Pure logic (config parsing, frame math, matching, state machines) must be testable without a running window server. The real AppKit/AX/CGEventTap adapters are thin and exercised only via opt-in integration tests.
- **No private-API Spaces work in v1.** Spaces support is a v2 feature.

## Layout

```
Package.swift              — SwiftPM, two targets: SlayoutCore (library) + Slayout (executable)
Sources/SlayoutCore/       — protocols + pure logic + AppKit/AX adapters
Sources/Slayout/           — main.swift + AppDelegate (menubar shell)
Tests/SlayoutCoreTests/    — Swift Testing tests against SlayoutCore
design-doc.md              — authoritative design (keep updated as decisions change)
```

## Build / test

- Build: `swift build`
- Run app (after granting Accessibility + Input Monitoring): `swift run Slayout`
- Tests: `swift test`

`swift test` requires Xcode (not just CommandLineTools), since the standalone CLT toolchain ships
neither XCTest nor the Swift Testing module. Tests are written using Swift Testing (`import Testing`,
`@Test` macros), bundled with Swift 6+ from Xcode.

If `swift test` fails with `no such module 'Testing'`:
`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`

## Build order (see design-doc.md §"Build order" for detail)

1. ✅ Skeleton: SwiftPM, AppDelegate, menubar stub, Permissions module.
2. ✅ Config TOML parsing (TOMLKit dep; `Config`, `HyperTrigger`, `WindowAction`, `MetaBindings`, `ConfigLoader.parse`).
3. ✅ ScreenProvider + Actions frame math (`ScreenInfo`, `ScreenProvider`, `Actions.tile`/`resolveScreen`/`moveToScreen`).
4. WindowServer protocol + FakeWindowServer.
5. AX adapter (live).
6. EventSource + Bindings.dispatch + CGEventTap + caps-lock→F18 remap.
7. LayoutStore capture/restore + matching.
8. Recorder state machine.
9. LastLayoutWatcher.
10. Polish: live reload, README.

Update this section's checkmarks as steps land.

## Conventions

- Swift Testing, not XCTest. Use `@Test func` and `#expect(...)`.
- Public API on `SlayoutCore` is what the executable + tests consume; everything else stays internal.
- Configuration paths: `~/.config/slayout/config.toml`, `~/.config/slayout/layouts.toml`.
- Application support: `~/Library/Application Support/Slayout/` for snapshots (`last-stable.json`, `pre-change.json`).
