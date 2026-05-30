# LLM-Suggested Tags — Implementation Plan
<!-- © Shimon Shmueli -->

Working plan for ZoneKey's "let an LLM classify my apps into my tags" feature.
Source of truth while we build; update in the same turn as any decision change.

> **Strategy revision (May 30):** dropped the original free-form "model proposes
> new tag names" approach. The model now picks only from the user's existing tag
> set. A new Stage-1 setup sheet lets the user curate that tag set before any
> network call, and the app ships out of the box with seven default seed tags.

---

## Locked decisions

- **Pro only.** Feature lives behind the existing compile-time Pro flag. In the Free build the
  Settings entry is visible but grayed out with an upgrade caption; no LLM or networking code
  ships in Free.
- **Providers:** Anthropic and OpenRouter at launch, behind a provider-agnostic `LLMClient` protocol.
- **Trigger:** manual only. A single "Suggest tags for my apps…" button in Settings.
- **Two-stage flow:**
  - **Stage 1 — Tag Setup sheet.** Editable list of the user's current tags (rename, recolor,
    delete, add, "Reset to defaults"). Nothing mutates until Continue. Cancel applies no diff.
  - **Stage 2 — Classification + Review sheet.** Classifier runs against the post-Stage-1 tag
    set; review sheet shows per-app accept/reject for the model's suggested existing-tag links.
- **Payload:** text-only — app name, bundle ID, and `LSApplicationCategoryType` from Info.plist.
  No icons, no plist descriptions, no telemetry.
- **Tag descriptions:** seeds-only. A tag whose name still matches a default seed sends its
  description in the prompt; renamed seeds and user-added tags send just the name.
- **Constrained model output:** existing tag IDs only. The model is forbidden from inventing new
  tag names; the wire schema has no `newTagNames` field.
- **Scope of a run:** untagged apps only. Cheapest and matches the common need. A future
  "reclassify all" mode can come later if asked for.
- **Review UX:** simplest possible. Per-row accept or reject only. Bulk actions limited to
  "Select ≥ 0.8" and "Reject all." Suggestions are additive — never removes an app from a tag.
- **Default seven seed tags** (also used as the out-of-the-box tag set for both Free and Pro):
  - Productivity — docs, notes, tasks, office, calendars
  - Creative — design, AV/image editing, music production, 3D
  - Development — IDEs, terminals, dev/API tooling
  - Communication — email, chat, calls, conferencing
  - Media — playback/consumption of video, music, podcasts, reading
  - Utilities — launchers, window/clipboard managers, system tweaks, maintenance, security
  - Lifestyle — games, finance, health, social, shopping, reference
- **Multi-tag per app** is allowed (the data model already supports it).
- **Default models:**
  - Anthropic: `claude-haiku-4-5-20251001`, `max_tokens: 8192`
  - OpenRouter: `anthropic/claude-haiku-4-5` (overridable in Settings), `max_tokens: 8192`,
    `response_format: {type: "json_object"}`
- **Batching:** 20 apps per LLM request (`Classifier.appsPerBatch`). Batches stitched into one
  validated list before the review sheet opens.
- **Key storage:** macOS Keychain via a thin local wrapper. One key slot per provider.
- **Entitlement:** `com.apple.security.network.client` already present in `Entitlements.plist`.

## Data flow

The classifier sends a single JSON object per batch containing the current tag set
(`[{id, name, description?}]`) and a slice of apps to classify (`[{bundleID, name, category}]`).
The model returns:

```
{
  "assignments": [
    { "bundleID": "com.foo.bar",
      "existingTagIDs": ["uuid…"],
      "rationale": "…",
      "confidence": 0.0–1.0 }
  ]
}
```

A validation pass drops any `existingTagIDs` that don't exist (model hallucination) and clamps
confidence to `[0,1]`. Nothing mutates `AppTag.items` or `AppItem.tags` until the user hits
Apply in the review sheet.

The Anthropic call uses the Messages API with the JSON-schema contract stated in the system prompt.
The OpenRouter call uses OpenAI-style `response_format: { type: "json_object" }`.

## Cache

Results persist to `~/Library/Application Support/ZoneKey/classification-cache.json`, keyed by
`(bundleID, appVersion, tagSetHash)`. A subsequent run only sends apps whose tuple isn't cached.
`tagSetHash` is SHA-256 over the sorted, lowercased tag-name set, so renaming, deleting, or
adding a tag correctly invalidates the cache for everything (the model's "existingTags" payload
changed). On format mismatch the cache silently rebuilds.

## Code layout

| File | Role |
|---|---|
| `Sources/Satus/Backend/DefaultTags.swift` | Seven seed tags + descriptions + colors. Both builds. |
| `Sources/Satus/Backend/KeychainStore.swift` | Read/write API keys by provider. Both builds. |
| `Sources/Satus/Backend/Classification/LLMClient.swift` | Protocol + request/response DTOs + shared diagnostic. Pro only. |
| `Sources/Satus/Backend/Classification/AnthropicClient.swift` | Anthropic Messages API impl. Pro only. |
| `Sources/Satus/Backend/Classification/OpenRouterClient.swift` | OpenRouter (OpenAI-style) impl. Pro only. |
| `Sources/Satus/Backend/Classification/Classifier.swift` | Prompt assembly, validation, cache, batching. Pro only. |
| `Sources/Satus/Views/TagSetupSheet.swift` | Stage-1 sheet (curate tags before classifying). Pro only. |
| `Sources/Satus/Views/ReviewSuggestionsSheet.swift` | Stage-2 sheet (accept/reject per-app). Pro only. |

## UI

Two surfaces in Settings → Tag Suggestions (Pro):

1. **Settings section:** provider picker (Anthropic / OpenRouter), API key (Keychain), optional
   OpenRouter model override, "Suggest tags for my apps…" button, inline status with a
   copy-to-clipboard button (kept permanently).
2. **Sheets:** Stage 1 (TagSetupSheet) → Stage 2 (ReviewSuggestionsSheet). Both modally
   presented over Settings.

## Build order (each step ≈ one milestone commit)

1. ✅ `KeychainStore` + Settings UI shell (both builds, grayed in Free).
2. ✅ `LLMClient` protocol + `AnthropicClient`; one-app round-trip smoke test.
3. ✅ `OpenRouterClient` against the same protocol.
4. ✅ `Classifier` orchestration, validation pass, cache, batching, copy-status button.
5. ✅ Two-stage flow: seven seed tags, `DefaultTags`, `TagSetupSheet`, constrained prompt,
   simplified `ReviewSuggestionsSheet`.
6. Polish: rate-limit handling, error states beyond what the diagnostic already shows.

## Defaults locked unless revisited

- Confidence threshold for "Select ≥ 0.8" bulk action: 0.8.
- Run scope on each press of the button: untagged apps only.
- New-tag rows added in the Tag Setup sheet default to neutral gray (`#8E8E93`) — user picks color.
- No app-list logging beyond the cache file. No analytics.
- `freeTagLimit = 3` unchanged — Free installs seed seven tags but can't add an eighth. Revisit
  if the limit collides with real usage.

## Explicitly out of scope for v1

- Stage-0 user-profile/occupation questions to auto-tune the taxonomy.
- "About me" free-text context field passed to the classifier.
- Automatic / background classification on new-app detection.
- Vision (sending icons).
- Drag-to-different-tag or inline edit of suggestions in the review sheet.
- "Reclassify all apps" mode.
- Removal suggestions (model proposing to un-tag an app).
- Local-model option (Ollama or similar).
- Persisted description field on `AppTag` for user-added or renamed tags.
