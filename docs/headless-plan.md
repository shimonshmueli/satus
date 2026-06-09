# Headless Apps — Implementation Plan
<!-- © Shimon Shmueli -->

Plan for extending ZoneKey to view and act on headless (non-GUI) software
installed on the machine: package-manager-installed tools and background
services. Source of truth while we build; update in the same turn as any
decision change.

---

## Locked decisions

- **v1 scope is comprehensive read-only.** Sources covered:
  - **Homebrew** (formulae + casks) — the primary, highest-signal source.
  - **npm global** packages (`npm ls -g --depth=0 --json`).
  - **pip / pipx** packages (`pipx list --json`, `pip list --format=json`).
  - **cargo install --list** binaries.
  - **mise / asdf** managed runtimes (`mise ls --json`, `asdf list`).
  - **LaunchAgents and LaunchDaemons** in `~/Library/LaunchAgents`,
    `/Library/LaunchAgents`, `/Library/LaunchDaemons`.
- **No execution in v1.** Every action either copies a command to the
  clipboard or opens Terminal with the command pre-typed. ZoneKey itself
  invokes no shell that mutates state. This makes v1 impossible to break
  your environment with.
- **v2 (later) adds direct execution** — `brew upgrade`, `npm install -g`,
  enable/disable LaunchAgents, bulk "update all outdated." Each gated behind
  a confirmation dialog. The execution layer is Pro-only.
- **Free/Pro split:**
  - Free: full read-only viewer.
  - Pro: direct execution, bulk actions, scheduled background refresh.
- **UI placement:** new **Headless** sidebar entry, alongside All Apps /
  Open Apps / Utilities / Untagged. Selecting it swaps the main content for
  a backend-aware list with a filter row across the top (All / Homebrew /
  npm / pip / cargo / mise / LaunchAgents). Single entry, internal filtering
  — keeps the sidebar quiet.
- **Branch:** before any code, `git checkout -b feature/headless`. v1 lands
  via PR or merge into `main`.

## Architecture

Two distinct concepts, two protocols.

### 1. Package managers

```swift
protocol PackageManager {
    static var id: String { get }              // "homebrew", "npm", "pip", …
    static var displayName: String { get }     // "Homebrew", "npm (global)", …
    static var isAvailable: Bool { get }       // does the CLI exist on $PATH?

    func list() async throws -> [PackageRecord]
    func outdated() async throws -> [PackageRecord]
    func dependencies(of: PackageRecord) async throws -> [String]
    func reverseDependencies(of: PackageRecord) async throws -> [String]
}

struct PackageRecord: Identifiable, Hashable {
    let id: String                  // backend-id + "|" + package-id
    let backendID: String           // "homebrew"
    let name: String                // "git"
    let version: String?            // "2.50.0_1"
    let latestVersion: String?      // nil if up-to-date or unknown
    let summary: String?            // one-line description
    let homepage: URL?
    let installedAt: URL?           // for "Show in Finder"
    let kind: Kind                  // .formula, .cask, .global, .runtime, …

    enum Kind: String, Codable {
        case formula, cask, npmGlobal, pip, pipx, cargo, mise, asdf
    }
}
```

Each backend is its own Swift file under `Sources/Satus/Backend/Headless/`:

| File | Backend |
|---|---|
| `PackageManager.swift` | Protocol + `PackageRecord` + shared shell helpers |
| `HomebrewBackend.swift` | `brew list/info/outdated/deps/uses --json` |
| `NpmBackend.swift` | `npm ls -g --depth=0 --json`, `npm outdated -g --json` |
| `PipBackend.swift` | `pip list --format=json`, `pip list --outdated --format=json`, `pipx list --json` |
| `CargoBackend.swift` | `cargo install --list` (text parse — no JSON option) |
| `MiseBackend.swift` | `mise ls --json` |

Backends shell out via a small `Shell` helper that wraps `Process` /
`URLSession`. Stdout-only, no shell injection (use argument arrays).
Each backend caches results in memory keyed by call timestamp; explicit
refresh button invalidates.

### 2. LaunchAgents / LaunchDaemons

Different model: not packages, but plist-defined services.

```swift
struct LaunchService: Identifiable, Hashable {
    let id: String                  // plist Label
    let path: URL                   // location of the .plist
    let scope: Scope                // userAgent / globalAgent / globalDaemon
    let program: String?            // ProgramArguments[0] or Program key
    let isLoaded: Bool              // from `launchctl list`
    let isEnabled: Bool             // from `launchctl print-disabled <domain>`

    enum Scope: String { case userAgent, globalAgent, globalDaemon }
}

enum LaunchServiceCatalog {
    static func scan() async -> [LaunchService]
}
```

Scans three directories, parses each plist, joins with `launchctl list`
output. Read-only; v2 adds enable/disable via `launchctl bootstrap` /
`bootout`.

## UI plan

### Sidebar

One new entry: **Headless**. Selecting it pushes a new view onto the main
content area — `HeadlessView` — that has:

- **Top filter row:** All / Homebrew / npm / pip / cargo / mise / Launch
  (chips). Only chips for backends that are `isAvailable` are shown.
- **Search field** to filter the visible list by name.
- **Sort menu:** Name / Version / Outdated-first / Backend.
- **Outdated badge** on backend chips: small red number for count.

### Row layout

Same width as app rows, dense:

```
[icon]  <name>  <version>   <outdated chip if any>   <short summary>
       homebrew · cask · /opt/homebrew/Caskroom/x       [actions ▾]
```

`icon` is a SF Symbol per backend (e.g. `mug.fill` for homebrew, `terminal`
for cli tools, `gear.badge` for LaunchAgents).

### Per-row actions (v1)

Right-click context menu:

- **Open homepage** (if `homepage` is set)
- **Show in Finder** (if `installedAt` is set)
- **View dependencies** — opens a popover with two columns: "Depends on"
  and "Used by"
- **Copy update command** — copies e.g. `brew upgrade git` to clipboard
- **Open Terminal with command** — opens Terminal.app and runs `osascript`
  to type the upgrade command into the front window (does **not** press
  Enter — user reviews and runs)
- **Copy uninstall command** — for completeness
- **PRO: Update** — disabled in Free build with `Update ⌈PRO⌋` label

### Detail popover

Click a row → small popover with: full description, license, homepage,
install date, full dependency tree (collapsible), reverse dependency tree.

## Build order (each step ≈ one milestone commit)

1. **Branch** `feature/headless` + scaffold `Sources/Satus/Backend/Headless/`
   with `PackageManager` protocol, `PackageRecord`, `Shell` helper, and a
   stub `HomebrewBackend` that just returns `brew list --json=v2` parsed
   into records.
2. **Headless sidebar entry + HeadlessView shell** with the filter row,
   search, sort. Homebrew tab only, listing records. Click a row → noop.
3. **Outdated detection + indicator chips** via `brew outdated --json=v2`.
   Refresh button. Cache TTL 1h.
4. **Per-row actions** (copy command, open homepage, Show in Finder).
   Open Terminal with command pre-typed via `osascript`.
5. **Dependency popover** (`brew deps`, `brew uses`) — both directions.
6. **npm backend** — same protocol, new backend file. Filter chip.
7. **pip + pipx backend.** Filter chip.
8. **cargo backend.** Filter chip.
9. **mise / asdf backend.** Filter chip.
10. **LaunchService scanner + viewer** — separate model, similar row layout.
    Filter chip "Launch."
11. **Polish**: sort modes, persistent filter selection in `@AppStorage`,
    pixel polish on chips and icons, accessibility labels.

Merge `feature/headless` into `main` after step 11. Tag as v1.2.

## Defaults locked unless revisited

- Shell calls use absolute paths probed at startup (`which brew`, `which
  npm`, …). Tools not found are simply not shown.
- All shell calls run with `Process`, argument array form (no shell
  interpolation), 15s timeout each.
- No file watching for changes; rely on user-initiated refresh.
- LaunchAgent plist parsing tolerates malformed plists by skipping them
  with a logged warning.
- The status / row count text uses the same copy-button pattern as the
  AutoTag inline status, for parity.

## Explicitly out of scope for v1

- Direct execution of any state-mutating command (deferred to v2).
- Docker / Podman container management.
- System frameworks, dylibs, kernel extensions.
- Cross-ecosystem dependency graph (e.g. "this brew formula needs a
  python from pyenv").
- App Store CLI tools via `mas`.
- Search-and-install a new package (vs. just managing installed ones).
- Browsing remote registries (Homebrew taps, npm registry).
- Per-package security advisories.

## Open questions to figure out as we build

- **Performance.** `brew list --json=v2` is ~1s for a typical machine,
  ~5s for a power user with many formulae. Do we block the UI on first
  load, show a skeleton, or load incrementally? Probably skeleton +
  progressive replacement.
- **mise vs asdf coexistence.** Some users have both; mise reads asdf's
  shims. Worth detecting and deduping.
- **Cargo's lack of JSON.** `cargo install --list` is human-formatted.
  We'll write a hand-rolled parser and add a small regression test.
- **Reverse deps cost.** `brew uses --installed <pkg>` runs per package
  and is slow at scale. Compute lazily on demand, not eagerly for the
  whole list.

## v2 preview (informational)

- Direct execution of upgrade/install/uninstall, gated by confirmation
  dialogs and a "dry-run" toggle that shows what would happen.
- Bulk "Update all outdated" per backend.
- Background refresh on a schedule (Pro setting).
- LaunchAgent enable/disable.
- The Pro upsell pitch (AutoTag + Headless execution) lives in Settings
  Pro section.
