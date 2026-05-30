# LLM-Suggested Tags — Implementation Plan
<!-- © Shimon Shmueli -->

Working plan for ZoneKey's "let an LLM propose tag assignments for my apps" feature.
Source of truth while we build; update in the same turn as any decision change.

---

## Locked decisions

- **Pro only.** Feature lives behind the existing compile-time Pro flag. In the Free build the
  Settings entry is visible but grayed out with an upgrade caption; no LLM or networking code
  ships in Free.
- **Providers:** Anthropic and OpenRouter at launch, behind a provider-agnostic `LLMClient` protocol.
- **Trigger:** manual only. A single "Suggest tags for my apps…" button in Settings.
- **Payload:** text-only — app name, bundle ID, and `LSApplicationCategoryType` from Info.plist.
  No icons, no plist descriptions, no telemetry.
- **Scope of a run:** **untagged apps only.** Cheapest and matches the common need. A future
  "reclassify all" mode can come later if asked for.
- **Review UX:** simplest possible. Per-row **accept or reject** only. No drag-to-different-tag,
  no inline editing of the model's suggestion in v1. Bulk actions limited to
  "select all high-confidence (≥ 0.8)" and "reject all."
- **Suggestions are additive.** The model never proposes removing an app from a tag.
- **Multi-tag per app** is allowed (the data model already supports it).
- **Default models:**
  - Anthropic: `claude-haiku-4-5-20251001`
  - OpenRouter: `anthropic/claude-haiku-4-5` (overridable as free-text in Settings)
- **Key storage:** macOS Keychain via a thin local wrapper. One key slot per provider.
- **Entitlement change:** add `com.apple.security.network.client` to `Entitlements.plist`.

## Data flow

The classifier sends a single JSON object containing the current tag set
(`[{id, name}]`) and the apps to classify (`[{bundleID, name, category}]`). The model returns:

```
{
  "assignments": [
    { "bundleID": "com.foo.bar",
      "existingTagIDs": ["uuid…"],
      "newTagNames": ["Writing"],
      "rationale": "…",
      "confidence": 0.0–1.0 }
  ]
}
```

A validation pass then drops any `existingTagIDs` that don't exist, normalizes `newTagNames`
(trim, length cap, alphanum + space, case-insensitive dedup against existing tags), and clamps
confidence to `[0,1]`. Nothing mutates `AppTag.items` or `AppItem.tags` until the user hits Apply
in the review sheet.

The Anthropic call uses the Messages API with the JSON-schema contract stated in the system prompt.
The OpenRouter call uses OpenAI-style `response_format: { type: "json_schema", … }`.

## Cache

Results persist to `~/Library/Application Support/ZoneKey/classification-cache.json`, keyed by
`(bundleID, appVersion, tagSetHash)`. A subsequent run only sends apps whose tuple isn't cached.
`tagSetHash` is a hash of the sorted tag-name list, so adding or renaming a tag correctly
invalidates the cache for everything (the model's "existing tags" context changed).

## Code layout

Five new files, one concern each:

| File | Role |
|---|---|
| `Sources/Satus/Backend/KeychainStore.swift` | Read/write API keys by provider. |
| `Sources/Satus/Backend/Classification/LLMClient.swift` | Protocol + request/response DTOs. |
| `Sources/Satus/Backend/Classification/AnthropicClient.swift` | Anthropic Messages API impl. |
| `Sources/Satus/Backend/Classification/OpenRouterClient.swift` | OpenRouter (OpenAI-style) impl. |
| `Sources/Satus/Backend/Classification/Classifier.swift` | Prompt assembly, validation, cache. |

The whole `Classification/` folder compiles only under the Pro flag.

## UI

Two surfaces:

1. **Settings → Tag suggestions (Pro)**: provider picker (Anthropic / OpenRouter), API key field
   (Keychain-backed), optional model override for OpenRouter, and the "Suggest tags for my apps…"
   button. In Free build the section is `.disabled(true)` with the upgrade caption.

2. **Review sheet**: opens when the run completes. Top block lists any new tag names the model
   proposes, each with a checkbox (default checked) and an auto-assigned color swatch (editable).
   Below, one row per app: icon, name, current tags, suggested additions as static chips,
   rationale on hover, accept/reject per row. Footer: "Apply N changes" / "Cancel."
   Bulk actions: "select all high-confidence (≥ 0.8)" and "reject all."

## Build order (each step ≈ one milestone commit)

1. `KeychainStore` + Settings UI shell (both builds, grayed in Free). Verifies gating works
   before any networking exists.
2. `LLMClient` protocol + `AnthropicClient`; manual one-app round-trip test.
3. `OpenRouterClient` against the same protocol.
4. `Classifier` orchestration, validation pass, cache.
5. Review sheet.
6. Polish: rate-limit handling, error states, cache invalidation on tag rename.

## Defaults locked unless revisited

- Confidence threshold for "select all high-confidence" bulk action: **0.8**.
- New-tag colors auto-assigned from a small palette, editable in the review sheet.
- No app-list logging beyond the cache file. No analytics.
- Run scope on each press of the button: untagged apps only.

## Explicitly out of scope for v1

- Automatic / background classification on new-app detection.
- Vision (sending icons) for low-confidence cases.
- Drag-to-different-tag or inline edit of suggestions in the review sheet.
- "Reclassify all apps" mode.
- Removal suggestions (model proposing to un-tag an app).
- Local-model option (Ollama or similar).

## Open / deferred

Nothing blocking. Anything in "out of scope" can be promoted to a v2 plan if usage warrants it.
