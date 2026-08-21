# Student UI Rebuild — Repo Audit & Implementation Plan

Date: 2026-08-19
Branch: `agent/student-ui-rebuild-v1`

## Product direction

Student app is a reading-first personal Bible app. Bible Reader is the visual and interaction core. Social/feed/gamified IA is explicitly out of scope. AI Bible interpretation/chat is not to be introduced.

## Audit classification

### 1. Keep directly

- Bundled CUV Bible asset and in-memory Bible repository/search foundation.
- SQLite local user data storage and DB migration framework.
- Web IndexedDB/sqflite compatibility layer.
- Firebase Auth integration and guest/offline-first startup behavior.
- Firestore multi-table LWW sync and tombstones/deletion sync.
- Firestore web forced long-polling and startup timeout safeguards.
- Existing persisted theme/font/last-reading settings.
- Existing reading log and last reading position persistence.
- Existing sermon note import/export codec.
- Existing app_links verse-opening capability.

### 2. Keep data/behavior, redesign UI

- Home.
- Bible Reader (`ChapterScreen`).
- Book/chapter selection.
- Search results and search history.
- Bookmark/highlight/note center.
- Reading plans.
- Sermon notes.
- Prayer.
- Settings/account/sync surfaces.
- Book overview/guide surfaces.

### 3. Modify

- Navigation: old push-from-home tool grid -> Home / Bible / Plans / Notes / Me shell.
- Reader interaction: converge existing verse action drawer into simple selection-first contextual actions; multi-verse selection needs explicit support.
- Home: remove feature-directory role; prioritize continue reading, today's plan, daily verse, recent personal content.
- Notes: make scripture notes + sermon notes one first-level destination; bookmarks/highlights remain secondary saved views.
- Plans: existing built-in plans/progress are reusable, but official/custom plans, daily state, missed-day rescheduling and published content need repository-backed redesign.
- Prayer model/UI: current category/subcategory/content model does not represent requested lifecycle statuses and scripture links cleanly.
- Reading activity: existing log/progress data should be presented as history/progress/stats rather than faith-map/gamified framing.
- Guides: current book-level annotation system is reusable, but new product requires clearly separated book and chapter editorial content with published-content semantics.

### 4. Missing / incomplete

- Full custom reading plan authoring.
- Missed-reading rescheduling strategies.
- Multi-verse selection as a first-class reader interaction.
- `Later` / deferred verse handling.
- Unified ScriptureLink widget with preview and source-aware back stack.
- Translation entitlement/catalog layer for licensed translations.
- User-selectable multi-translation comparison beyond current bundled KJV behavior.
- Prayer statuses: praying / answered / ended, plus verse links.
- Dedicated reading activity UI (history / book progress / statistics).
- Notification preferences/reminders UI and scheduling integration.
- Full personal data export covering all requested user content.
- Published daily verse / official plans / chapter guide repository contracts where backend data is not yet available.

### 5. Hide/remove from new primary IA

- Q&A as a general student AI/chat-like primary destination.
- Voice Q&A primary entry.
- Knowledge base as a primary Home destination.
- Faith map as a primary/gamified destination.
- Topic/mood feature grid as a primary Home destination.
- Faith-life Todo as a primary destination; keep stored data for compatibility, but do not make the app a Todo app.

No destructive DB migration or deletion is part of the UI rebuild. Hidden legacy features/data remain intact unless a later migration is explicitly approved.

## Implemented in first integration pass

- Added five-destination `AppShell`.
- Added reader-centered Home.
- Added Bible hub.
- Added unified Notes hub.
- Added Me hub for prayer/settings/secondary features.
- Kept Reader as a full-screen pushed route, so bottom navigation disappears while reading and source-aware Navigator back stack is preserved.
- Kept existing data providers/repositories rather than duplicating storage.
- Kept loading/empty/error handling on the new Home surface.

## Backend Required

Do not invent these shapes in Flutter. Add repository interfaces/placeholders until backend contracts are finalized.

1. **Published daily verse**: published item identity, verse reference, active date/window, locale/translation metadata.
2. **Official reading plans**: published plan metadata, ordered day items, versioning/publication status; user progress remains user data.
3. **Custom reading plans**: decide whether custom plan definition is local+sync user data or backend-managed; needs stable IDs and deletion semantics.
4. **Plan rescheduling**: persistent schedule/version semantics if rescheduling must sync across devices.
5. **Book/chapter guides**: published editorial content contract that clearly identifies content type/source/status/version.
6. **Translation catalog/licensing**: available translations, entitlement/licensing flags, downloadable/offline availability and version.
7. **Prayer v2**: status, scripture references, lifecycle timestamps and sync/tombstone support.
8. **Later/deferred verses**: user-data entity with stable ID, verse range, timestamps and sync/tombstone support.
9. **Notification preferences**: user preferences and, if server-driven, FCM/device token + schedule semantics.
10. **Reading activity definition**: authoritative rules for what counts as a read chapter/verse before UI exposes progress statistics.
11. **Personal export**: backend/cloud export contract if export must include remote-only content or account metadata.
12. **Reviewed Q&A only**: any future student Q&A endpoint must return only admin-provided, reviewed, published source material and an explicit insufficient-reviewed-content state. No web/model fallback is allowed.

## Validation expectations

Before merge/deploy, run Flutter analyze, tests, student web build and admin web build. Verify mobile layout, web/PWA, light/dark, Reader back stack, existing local data, offline startup and signed-in sync. The GitHub connector can edit/review repository content but does not provide a Flutter runtime, so runtime checks must execute in CI or a Flutter-capable checkout before this branch is merged.
