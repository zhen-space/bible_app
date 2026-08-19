# Release Integration Review — v1

Date: 2026-08-19
Integration branch: `agent/release-integration-v1`
Status: **Release review. NOT merged to production. NOT deployed.**

## Scope of this integration

Safe integration of the front-end and back-end foundation work, with a
correctness fix to Q&A access control, followed by full validation.

### Branches reviewed

| Branch | Relation | Notes |
|---|---|---|
| `claude/bible-app-setup-xi8bvd` | base/mainline | reader app + prior fixes (login/sync, 私名號, verse-focus, sermon IO) |
| `agent/student-ui-rebuild-v1` | base + 7 commits | reader-first 5-destination student shell (Home/Bible/Plans/Notes/Me); PR #1 (draft) |
| `agent/backend-gap-foundation` | == mainline HEAD | **no unique commits**; "backend foundation" is the placeholder/contract work in the audit, of which reviewed-only Q&A is the one concrete item implemented here |
| `agent/release-integration-v1` | student-ui + 2 commits | **this branch**: Q&A published gating + navigation test/IA update |

The integration branch was built off `agent/student-ui-rebuild-v1` because it
already contains the full base (front) and there is no separate back-end code to
merge; `backend-gap-foundation` points at mainline HEAD.

## Correctness fix — Q&A: only Published content reaches students

**Requirement:** only `published` content is retrievable by the student side;
`approved`/`reviewed` ≠ `published`; with no published data the app must not
answer (no fallback to unpublished/approved content, and no AI/web fallback).

**Before:** answering a question set `status:'approved'`, which was immediately
student-visible — including the voice Q&A "existing answers" keyword match.
There was no `published` concept. The Firestore rule exposed any
`status == 'approved'` doc for public read.

**After (enforced at three layers):**

1. **Data model** — `Question.published` (default `false`). Parsing an
   `approved` doc that has no `published` field yields `published == false`
   (guarded by a unit test).
2. **Service / providers** — answering sets `approved` but never publishes;
   `setPublished()` is a separate admin action. Student reads go through
   `publishedQuestions()` (`published == true` **and** answered) via
   `publishedQuestionsProvider`. Voice Q&A matches published only and shows an
   explicit "no published answer — submit to the church" state when empty.
   Admin gets an `awaitingPublishQuestions()` queue.
3. **Firestore rules** — public read requires `resource.data.published == true`
   (not `status == 'approved'`); create must set `published == false` (a user
   cannot self-publish); publish/answer/approve are admin-only writes.

Defence in depth: Q&A is also not linked from the new student primary IA, and
admin publish controls are `isAdmin`-gated. Admin workflow remains operable via
the admin app: dashboard → Q&A → review/answer → awaiting-publish queue →
Publish.

## Validation results

| Check | Result |
|---|---|
| `flutter analyze` | ✅ No issues |
| `flutter test` (full suite) | ✅ 43 tests pass (incl. new Q&A published + proper-name + IO tests) |
| Student web build (`main.dart`) | ✅ Built `build/web` |
| Admin web build (`main_admin.dart`) | ✅ Built `build/web` |
| DB migration/schema | ✅ v8; `_onUpgrade` covers v2–v8; all 9 tables in `_createAllTables`; unchanged by this integration |
| Firestore rules | ✅ Consistent; Q&A published-gate enforced server-side; no remaining `status=='approved'` public read |
| Core flow — reader | ✅ Navigation test drives new IA (聖經 tab → 選擇書卷與章節 → BooksScreen → chapter → verses + 導讀/統整 boxes) |
| Core flow — Q&A publish | ✅ Workflow operable and gated (verified by code review + unit test) |

## Fixes applied during integration

- **Navigation test** updated to the new student-shell IA (the rebuild replaced
  the old feature-directory home; the test drove the old home and failed).
  Added the missing `material` import for `NavigationBar`.
- **Q&A published gating** implemented end-to-end (above).

## Not done (by design / out of scope)

- **No production merge, no deploy.** This branch stops at review.
- Remaining backend contracts from `docs/STUDENT_UI_REBUILD_AUDIT.md`
  (published daily verse, official/custom plans, plan rescheduling, book/chapter
  guides, translation catalog/licensing, Prayer v2, Later items, notifications,
  reading-activity rules, personal export) are **not** implemented — they need
  backend contracts first, per the audit. Only reviewed-only Q&A was concrete
  enough to implement now.

## Residual risks / follow-ups for release

1. **Runtime smoke of the new shell destinations** (Home / Plans / Notes / Me)
   in a real browser (light/dark, mobile layout, back stack, offline start,
   signed-in sync) — a Flutter web runtime is required and is a manual/CI step;
   this environment validated compile + widget tests only.
2. **Existing approved-but-unpublished Q&A** will disappear from student view
   until an admin explicitly publishes each — this is the intended stricter
   behavior; confirm it is acceptable for any existing data.
3. **Firestore rules deploy**: the rule change must be deployed
   (`firebase deploy --only firestore:rules`) for the server-side gate to take
   effect; app-side gating alone is not sufficient.
