# IDE Toolbox

A menu bar app for macOS that installs, updates and launches the lai3d native IDEs, in the spirit of JetBrains Toolbox. Swift (SwiftUI + AppKit), no third-party dependencies.

| App | Repo | Launcher |
|---|---|---|
| GoIDE | [lai3d/golang-ide](https://github.com/lai3d/golang-ide) | `goide .` |
| PyIDE | [lai3d/python-ide](https://github.com/lai3d/python-ide) | `pyide .` |
| JavaIDE | [lai3d/java-ide](https://github.com/lai3d/java-ide) | `javaide .` |
| CSharpIDE | [lai3d/csharp-ide](https://github.com/lai3d/csharp-ide) | `csharpide .` |
| RustIDE | [lai3d/rust-ide](https://github.com/lai3d/rust-ide) | `rustide .` |
| CppIDE | [lai3d/cpp-ide](https://github.com/lai3d/cpp-ide) | `cppide .` |
| PHPIDE | [lai3d/php-ide](https://github.com/lai3d/php-ide) | `phpide .` |
| ESPIDE | [lai3d/esp32-ide](https://github.com/lai3d/esp32-ide) | `espide .` |
| DBIDE | [lai3d/database-ide](https://github.com/lai3d/database-ide) | `dbide` |
| Grove | [lai3d/grove](https://github.com/lai3d/grove) | `grove .` |

## What it does

- **Install / update** from each repo's latest GitHub Release (the first `.zip` asset, preferring one named after the app) into `~/Applications`. The old copy goes to the Trash. Checks on launch and every 6 hours.
- **Launch** an app, or open a folder in it (the folder is passed as the first launch argument; a new instance is started if the IDE is already running).
- **Recent projects** for each IDE, one click to reopen.
- **Command-line launchers** (optional) in `~/.local/bin`. Existing files the Toolbox didn't write are never overwritten.

If the menu bar is too crowded to show the icon, launch with `open -a IDEToolbox --args --window`, or open the app again from Finder, to get the panel in a regular window. `--update-self` updates the Toolbox to the latest release and relaunches it.

## Adding an app

1. Add a `Tool` to `Sources/ToolboxCore/Catalog.swift`.
2. Give the repo a release workflow that publishes a zipped `.app` on `v*` tags (see `.github/workflows/release.yml`). `CFBundleShortVersionString` must match the tag for update detection.

## Recent-projects format

Each IDE writes `~/Library/Application Support/IDEToolbox/recents/<bundle-id>.json`, newest first:

```json
{ "projects": [ { "path": "/Users/me/code/app", "openedAt": "2026-10-31T13:00:00Z" } ] }
```

`RecentsStore.record(_:bundleID:)` in `ToolboxCore` is the reference implementation (about 15 lines to copy into an IDE). Apps that don't write the file yet can be read from a string-array key in their own defaults domain (`recentsDefaultsKey`, used for Grove).

## Build

```sh
swift test                                           # unit tests
TOOLBOX_NETWORK_TESTS=1 swift test --filter Network  # real download + install into a temp dir
./scripts/bundle.sh && open build/IDEToolbox.app
```

Apps are ad-hoc signed and not notarized. The Toolbox clears the quarantine flag on apps it downloads itself.
