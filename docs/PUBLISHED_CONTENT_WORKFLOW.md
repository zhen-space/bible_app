# Published-Content Workflow & Q&A Safety (#8 / #9)

本輪在 `agent/p0-backend-published-workflow`（以 PR #3 HEAD 為相容性基準）實作。
**未 deploy、未 merge、未跑 production migration、未連 production。**

## 1. Existing / Reuse / Modify / Missing / Migration

| 內容型別 | Existing | 本輪 Modify | Migration required |
|---|---|---|---|
| `questions`（Q&A） | 已有 `status`＋`published` gate（最佳範本） | 加 retrieval 安全契約、回答 source ids+versions | 無（沿用） |
| `annotations`（卷/章導讀、節註解、Book/Chapter Guides） | read-all、無 status | rules status-gated；client 只讀 Published＋快取只存 Published、無 asset fallback；admin 寫入 stamp published meta | **需 backfill**（補 status/version/provenance） |
| `knowledge` | 單 doc read-all、無 status | 同上（fail-closed） | **需 backfill** |
| `public_notes` | read-all、無 status | rules status-gated；loc+status 複合查詢（需 index）；approve 時 stamp published meta | **需 backfill** |
| `daily_verses` | #3 加的 `published` bool | rules status/published-gated；client fail-closed（無 pool fallback） | backfill 補 status（相容 `published==true`） |
| Reading Plans | client 端機械計畫；`plan_item_progress`（PR #3） | 定義 published 計畫 schema；`plan_item_progress` 加 stable `item_id`（DB v14） | 官方 Published 計畫內容＝Missing（需後台撰寫） |
| **Missing（需後端/後台）** | — | Draft→Review→Publish **admin UI**；官方計畫/每日經文的發佈編輯器；多管理員（custom claim） | — |

## 2. Schema（受管理內容通用外殼，扁平序列化以相容 legacy 讀取端）

每個受管理文件（published mirror 與 workspace 皆同）頂層欄位：

```
content_id   : string     # stable id
content_type : string     # book_guide/chapter_guide/verse_commentary/knowledge/daily_verse/public_note/reading_plan
status       : 'draft'|'review'|'published'|'rejected'|'archived'
version      : int         # 從 1；每次發佈 +1
created_at, created_by
updated_at, updated_by
reviewed_by, reviewed_at
published_by, published_at
archived_at              # 0＝未封存
provenance   : { source, note }
versions     : [ 舊 Published 快照… ]   # 只在 published mirror
<payload>    : 內容本身的欄位（與 meta 並存於頂層）
```

（讀取相容 legacy 舊欄名 `reviewer`/`publisher`；新寫入一律用 `reviewed_by`/`published_by`。）

- **published mirror** = 既有公開 collection（`annotations` / `knowledge` / `daily_verses` /
  `public_notes` / `reading_plans`）：**只放 Published**，學生端讀這裡。
- **workspace** = `<type>_workspace`：Draft/Review/Rejected/Archived 工作副本，**僅管理員**。
- **新 Draft 不覆蓋 Published**：草稿只寫 workspace；`approveAndPublish` 才把快照複製到
  mirror、`version+1`、舊快照推入 `versions`。
- SQLite `plan_item_progress`（DB v14）加 `item_id`：Published 計畫 Reading Item 用 stable
  item_id 作 **progress 身分**（非 display index）；機械計畫 item_id 空、沿用真實章位身分。

Dart：`lib/models/managed_content.dart`（`ManagedContent` / `ContentStatus` / `ContentProvenance`
/ `AnswerSource`）、`lib/services/content_workflow_service.dart`（工作流 API）。

## 3. API contract（工作流）

`ContentWorkflowService(type, contentId)`：
- `saveDraft`（只寫 workspace，回到 draft，不動 live Published）
- `submitForReview` → status=review
- `reject(reviewer)` → status=rejected（記 reviewer/reviewed_at）
- `approveAndPublish(publisher)` → 複製 workspace→mirror，version+1，publisher/published_at，
  舊 Published 快照入 `versions`
- `archive(publisher)` → mirror + workspace status=archived（學生端立即讀不到）

現行 admin 編輯器（`admin_screen` / `admin_knowledge_screen`）走「直接發佈」路徑
（`ContentService.saveBook/saveChapter/saveVerse/saveKnowledge`、`approveSubmission`），
已 stamp `status='published'`＋version+1＋provenance＋publisher，是合法 Published mirror doc。
分階段 Draft→Review→Publish 由 `ContentWorkflowService` 提供，admin UI 之後接。

## 4. Firestore rules（`firestore.rules`，硬性阻擋）

- 公開讀：`isPublished()`（`status=='published'`；`daily_verses` 相容 `published==true`）。
  Draft/Review/Rejected/Archived **讀不到**。
- `<type>_workspace`：`isAdmin()` only（學生端永遠讀不到草稿/送審）。
- 受管理 collection 寫入：`isAdmin()` only → 一般使用者**無法自改 status/reviewer/publisher**。
- `submissions`/`questions` create：限 `uid==auth.uid`＋`status=='pending'`（questions 另
  `published==false`）→ 無法自我發佈/核准。
- `users/{uid}/{**}`：本人 only（含所有私有子集合）。
- 其餘 default-deny。
- `public_notes` 依 `loc+status` 查詢 → `firestore.indexes.json` 複合索引。
- ⚠️ **部署順序**：先 backfill 補 status，再部署 rules，否則未補 status 的 legacy 對學生端 fail-closed。

**Rules 測試**：`tools/rules_test.mjs`（@firebase/rules-unit-testing）＝**18/18 通過**（emulator 實跑）。

## 5. Q&A safety enforcement（#9）

- **三態結果**（`QaService.ask` / `QaAskResult` / `QaOutcome`）：
  - `answered`：在 **Published approved** 語料以純關鍵字命中（回 matches：answer＋source scriptures/sources）。
  - `insufficient_approved_content`：找不到，**不得生成一般回答**（無模型知識／Web／LLM fallback）。
  - `pending_question_created`：使用者送出未回答問題（`submitQuestion` 回 id → `QaAskResult.pending`）。
- 語料 = **只有 Published（且已回答）**；pending/rejected/draft/review/未發布**永不進語料**。
  archive/unpublish 後即時退出（每次 `retrieveApproved` 直接查 `published==true` live，無 stale index）。
- 回答保存 `sources`（`AnswerSource` = content_id + **immutable** version + kind + evidence）→ 前台可取得回答依據與版本追溯。
- **Pending Question 本身不是 retrieval source**；管理員處理＝Pending → 建立內容 Draft → Review → Published，Published 後才可成為未來語料。
- 強制點在 service/API 層（`ask`/`retrieveApproved` 只查 Published），非只 client UI；Firestore rules 另擋直接讀未發布 question。

## 6. Cache / fail-closed（#10）

- 聖經經文 asset offline 保留；user private content offline-first 保留。
- admin content 快取只存**已確認 Published** 版本（`cache_annotations_published` /
  `cache_knowledge_published` / `cache_daily_$ymd`）。
- annotations/knowledge **移除 asset fallback**：cloud Published → Published 快取 → 空
  （不退回未驗證內容）。
- 每日經文：只讀 Published；無 → `null`＝「今日尚無經文」卡，**不 fallback pool/random/AI**。

## 7. Authorization audit

- Guest/student：只能讀 Published public content（rules 證明；Draft/Review/Rejected/Archived、workspace 皆讀不到）。
- authenticated user：只能讀寫自己的 `users/{uid}` 私有資料（他人 deny）。
- Admin：才能 create/review/publish/archive。
- **Admin 授權 backward-compatible**：rules `isAdmin()` = custom claim `admin==true` **或** legacy 單一 email
  （不破壞現有登入，多管理員走 claim）。client：`isAdminProvider`（email，同步）＋`adminClaimProvider`
  （ID token claim）＋`isAdminEffectiveProvider`（兩者取或）。設定 claim 由後端 Admin SDK（未做，屬部署步驟）。
- client 自改 status/reviewed_by/published_by：**不可能**（受管理 collection 非 admin 不可寫；
  submissions/questions create 限定欄位；student 不可 update 既有 question 發佈）。
- collection group / 直接讀 bypass：workspace 為 top-level collection，rules 逐一 admin-only，
  collection-group query（學生端）被拒（測試涵蓋）；未匹配 default-deny；`public_notes` 查詢帶 status
  讓 rules 可證明只回 Published。

### Reading Plans identity（#2 audit 結論）
`plan_item_progress` 身分 = `(plan_id, book_id, chapter)`（真實章位，**非** day/list display index，
換版不錯位）；另有 `item_id`（v14，Published 計畫 stable Reading Item id）與 `plan_version`（v15）
可辨識 v1→v2。機械計畫 item_id 空、plan_version=1。**不依賴 day display index / list index /
scripture position 順序**。

## 8. Migration / Backfill plan（`tools/`，本輪不執行）

1.（唯讀）`node tools/audit_published.mjs` — 盤點缺 status/version/provenance 的 legacy 文件。
2. `node tools/backfill_status.mjs`（dry-run）檢視計畫 → `--apply` 由**使用者本人**在可信環境跑：
   additive `set(merge)`，只補缺欄位、**不覆蓋既有 status/version、不刪資料、不改 payload**。
3.（唯讀）再跑 audit 驗證乾淨。
4. 部署 `firestore.rules` ＋ `firestore.indexes.json`（複合索引）。
- **fail-closed 已實測**：缺 credentials → exit 1；偵測 `FIRESTORE_EMULATOR_HOST` → 中止；
  絕不 fallback local/emulator；audit 全唯讀、backfill 預設 dry-run。

## 9. Tests / build（本輪實跑）

- `flutter analyze`：clean（tools/ 已排除於 Dart 分析）。
- `flutter test`：51/51（含 8 個 #8/#9 契約 unit test：ManagedContent round-trip／legacy 欄名相容／payloadOf／AnswerSource／QA 三態）。
- Firestore rules 測試：30/30（emulator，含 Draft/Review/Rejected/Archived deny、custom-claim admin、collection-group deny、student 不可自我發佈）。
- fail-closed 守門：audit/backfill 無憑證與 emulator 情境皆正確中止。
- Student build ✓、Admin build ✓。

## 10. 尚未完成（Missing / 需你本人）

- **需你本人一步**：在可信環境用 service account 跑 `backfill_status.mjs --apply`，再部署
  `firestore.rules` + `firestore.indexes.json`（本輪禁止 deploy/連 production）。**除此之外目前不需你操作。**
- Draft→Review→Publish 的 **admin UI**（服務層已就緒）；官方 Published 讀經計畫/每日經文的
  發佈編輯器與內容（⛔ 內容由使用者親撰）。
- 多管理員（custom claim 取代單一 email）為未來擴充點。
