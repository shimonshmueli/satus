# Satus — Project Instructions
<!-- © Shimon Shmueli -->

Shared collaboration discipline (scope, safety, style, output, conventions) lives in the
global `~/.claude/CLAUDE.md` and applies automatically. This file only adds Satus-specific notes.

---

## What this project is

Satus / ZoneKey is a native macOS app written in Swift using SwiftPM (see `Package.swift`,
`Sources/Satus/`). It ships in Free and Pro variants via a compile-time flag.

## Project scope

- "Work only inside the project tree" = `/Users/shimonshmueli/Desktop/Satus/` and its subfolders.

## Project-specific conventions

- Respect the existing Free / Pro compile-time split; don't blur the boundary without asking.
- Treat code-signing identities, notarization credentials, and `.p12` / API keys as off-limits
  unless explicitly invoked for a signing or notarization task.
- Prefer Apple primary sources (developer docs, WWDC sessions, Swift Evolution proposals) when
  citing external material.

## Project layout (quick map)

| Path | Purpose |
|---|---|
| `Package.swift` | SwiftPM manifest |
| `Sources/Satus/` | App source (Backend, Views, etc.) |
| `Satus/` | Xcode-side project assets |
| `Info.plist`, `Entitlements.plist` | App metadata and sandbox / capabilities |
| `Builds/`, `.build/` | Build outputs — do not hand-edit |
| `archive_app.sh`, `bundle_app.sh`, `notarize_app.sh` | Release pipeline scripts |
| `docs/` | Project documentation |
