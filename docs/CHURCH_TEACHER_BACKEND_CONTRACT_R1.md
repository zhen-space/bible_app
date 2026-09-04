# Church / Teacher Area — Backend Contract R1

狀態：**contract 定案（未實作、未 migration、未 deploy）**。這份把已定案的產品 hard
contracts 翻成可實作的 Firestore / repository / authorization 契約。內容文字仍由使用者親撰；
本檔只定資料契約與授權邊界。

## 0. 核心不變量（貫穿全契約）

1. **兩軸授權，`audience` 是 Student 對受管理內容的唯一 access authority**：
   `status` = 發佈狀態；`audience` ∈ `public | church | internal` = 對象授權。
   舊 `visibility(student/internal)` **不再是 Church 世界的 authority**（見 §7 演進）。
2. **Student 可讀 ⇔ `status=='published'` 且 audience 授權通過**。`public` 全學生可讀；
   `church` 僅「目前 Active Membership 的 churchId ∈ `allowedChurchIds`」；`internal` 永不可讀。
3. **authorization unknown = unauthorized**；缺 `audience`、`audience==church` 但
   `allowedChurchIds` 空、membership 不明 → 一律 **fail-closed**（deny）。
4. **Published ≠ Public**。Admin 有 bypass。
5. **Rules 不是 filter**：每個 list query 必須自帶授權述詞，rules 逐 doc 再驗；
   凡 query 回傳任一 doc 不符 rule，整個 query 失敗（見 §8/§16）。

---

## 1. Collections / paths（R1 全覽）

| path | 用途 | 寫 | 讀（Student） |
|---|---|---|---|
| `churches/{churchId}` | Church 公開表示（Picker） | Admin | active 者可讀（公開欄位） |
| `churches/{churchId}/private/admin` | Church 私有營運資料 | Admin | **deny** |
| `memberships/{uid}` | 使用者唯一 membership 記錄（doc id = uid） | 建立 pending＝本人；狀態＝Admin | 本人可讀自己 |
| `memberships/{uid}/history/{autoId}` | membership 變更稽核 | Admin | **deny** |
| `study_content/{id}` (+ `_workspace`, `/versions`) | 研讀內容（＝Teaching 本體） | Admin | published＋audience 授權 |
| `study_topics/{id}` (+ `_workspace`, `/versions`) | 主題 | Admin | published＋audience 授權 |
| `annotations/{id}` (+ `_workspace`, `/versions`) | 雲端註解（scripture-anchored） | Admin | published＋audience 授權 |
| `teacher_books/{bookId}` (+ `_workspace`) | 老師專區書卷（結構） | Admin | published＋audience 授權 |
| `teacher_books/{bookId}/chapters/{chapterId}` (+ 對應 workspace) | 章（結構） | Admin | published＋audience 授權 |
| `users/{uid}/saved_study_content/{contentId}` | 已存研讀內容（relationship only） | 本人 | 本人 |

Teaching **不建 `teacher_teachings`**：teaching body 就是 `study_content`，以
`teacher_book_id` / `teacher_chapter_id` reference 掛到章（§11/§12）。

---

## 2. Document schema（每個 collection）

### 2.1 `churches/{churchId}`（僅公開欄位）
```
church_id: string            // = doc id
name: string                 // 內容由 Admin 親填，不 hardcode denomination
region: string               // 選填，可公開的地區顯示
active: bool                 // Inactive 不可成為新 request/publish target
created_at: int
```
私有欄位（member 統計、營運）一律放 `churches/{churchId}/private/admin`，Student 永不讀。

Teacher Area capability 另存為精確的私有子文件：
```
churches/{churchId}/private/capabilities
teacher_area: bool
```
- 這是「Teacher Area 入口是否存在」的 authority，**不是**內容授權，也不由 Published
  Teaching count 推導。
- Student 只能 direct-get 自己 Active Membership 對應的 Church capability，不可 list／scan，
  也不可讀其他 Church；其餘 private 文件仍為 Admin-only。
- 缺 doc、缺 `teacher_area`、非 bool 或未知值一律視為 false（fail-closed）。

### 2.2 `memberships/{uid}`（doc id = uid → 結構性保證每人至多一筆 → 至多一個 Active）
```
uid: string                  // = doc id
church_id: string            // 申請/所屬 church
status: string               // pending | active | rejected | revoked
requested_at: int
reviewed_at: int
reviewed_by: string          // admin email/uid
rejected_at: int             // 0 = N/A
revoked_at: int              // 0 = N/A
```
- **no document / no valid request ⇒ no membership**（不為 none 造假授權）。
- **audit history**：每次狀態轉換 Admin append 一筆到 `memberships/{uid}/history/{autoId}`
  （`{from,to,at,by,church_id}`），Student 不可讀。

### 2.3 受管理內容 envelope（study_content / study_topics / annotations / teacher_books / chapters 共用）
沿用既有 `ManagedContent`（status/version/created_by/reviewed_by/published_by/provenance/
versions），**新增兩個 meta 欄位**（加入 `reservedKeys`，序列化在 doc 頂層供 rules 讀）：
```
audience: string             // public | church | internal   ← Student 唯一 authority
allowed_church_ids: [string] // 僅 audience==church 使用；public/internal 不作 authority
```
- `study_content` payload 另加 reference（§12）：`teacher_book_id?`, `teacher_chapter_id?`。
- `annotations` payload：`scripture_ref`（節位 identity）＋ `body`（§10）。
- `visibility` 欄位**保留但停用為 authority**（僅 legacy 顯示/相容；rules 不再據此放行）。

### 2.4 `teacher_books` / `chapters`（結構，無 teaching body）
```
// teacher_books/{bookId}
book_id, title, description?, order:int, status, audience, allowed_church_ids, <audit meta>
// teacher_books/{bookId}/chapters/{chapterId}
chapter_id, book_id, title, order:int, status, audience, allowed_church_ids, <audit meta>
```

### 2.5 `users/{uid}/saved_study_content/{contentId}`（§14 已 ratify）
```
content_id: string           // = doc id
saved_at: int
```
**只存 relationship**，不存 title/body/payload/audience/authorization snapshot。

---

## 3. Enum / state 定義

- `ContentStatus`（既有，不動）：`draft|review|published|rejected|archived`。
- **`Audience`（新）**：`public|student-合併? no` → 正式三值 `public|church|internal`。
  `fromName` 未知/缺失 → **null → fail-closed（視為 internal，不可對 Student 公開）**。
- `MembershipStatus`（新）：`pending|active|rejected|revoked`；缺 doc = none（非授權）。
- `AnswerSource.access`（既有欄位，擴充語意）：`public|church|internal`（study_content）
  或 `''`（scripture）。

---

## 4. References（跨 doc 關聯）

- `memberships/{uid}.church_id → churches/{churchId}`。
- 受管理內容 `allowed_church_ids[] → churches/{churchId}`（audience==church）。
- `study_content.teacher_book_id → teacher_books/{bookId}`；
  `study_content.teacher_chapter_id → teacher_books/{bookId}/chapters/{chapterId}`。
- `users/{uid}/saved_study_content/{contentId} → study_content/{contentId}`（僅 id）。
- `answer.sources[].content_id → study_content/{id}`（open-time live resolve）。

---

## 5. Authorization authority（誰說了算）

| 判斷 | authority |
|---|---|
| Student 能否讀某內容 | 該 doc 的 `status==published` ＋ `audience`（＋ `memberships/{uid}` 若 church） |
| 目前 active churchId | **`memberships/{uid}`（Admin-authoritative，Student 不可自寫 status/church_id）** |
| Membership 狀態 | `memberships/{uid}.status` |
| Church 是否可申請/發佈 | `churches/{churchId}.active` |
| Teacher Area 入口是否存在 | Active Membership＋Active Church＋該 Church private `capabilities.teacher_area==true` |
| Saved 能否開啟 | **open-time** 走 authorization-aware repo（saved doc 不是 authority） |
| Q&A citation 能否開啟 | open-time re-resolve（snapshot 不是 authority） |

**關鍵**：membership 授權來源 `memberships/{uid}` **必須 Admin-only 才能設 `status/church_id`**，
否則使用者自寫即可提權。故不放在 owner-writable 的 `users/{uid}` 子樹（見 §5 決策）。

---

## 6. Membership invariant（在哪層 enforce）

- **「一 User 至多一個 membership 記錄」＝ doc id = uid 結構性保證**（Firestore 天然唯一）。
- **「至多一個 Active」** 因此也結構性成立（同一 doc 的 `status` 至多一個值）。
- **第二個 church 的 approval blocking**：因 doc-id=uid，加入 church B 前必須先 revoke
  church A（重用同一 doc）。R1 取此最強不變量。
- **tradeoff（需產品一句話確認，非重新設計）**：R1 不支援「A 仍 active 時對 B 有 pending」。
  若未來要並存，改為 `membership_requests/{autoId}` + `memberships/{uid}` active pointer；
  R1 **建議** doc-id=uid（Admin list = query `status==pending`；uniqueness 免 transaction）。

---

## 7. Study Content audience 演進（不留雙 authority）

**決策：`audience` 成為唯一 Student authority；rules 不再讀 `visibility` 放行。**

legacy → audience 映射（migration，見 §19；**只讀不自動擴大 exposure**）：
| legacy | audience | 理由 |
|---|---|---|
| `published` ＋ `visibility==student` | **public** | 原本即全學生可見＝公開 |
| `visibility==internal`（任何 status） | **internal** | 維持內部 |
| **missing audience** | **internal（fail-closed）** | 未判定不得曝光 |
| `audience==church` 且 `allowed_church_ids` 空 | **fail-closed**（deny＋不可送審/發佈） | 無對象＝不授權 |

**部署順序硬性**：**先 migration 補 `audience`，再 deploy 新 rules**。否則新 rules 上線時
未補 audience 的 legacy student 內容會立即 fail-closed（讀不到）——安全但會短暫隱藏，故順序不可反。

---

## 8. Authorized Study Content query contract（repository 邊界）

Repository 組「Authorized Universe」＝下列 query 的 union（client 合併），**絕不 fetch-all-then-hide**：

```
PUBLIC:
  study_content.where(status==published).where(audience==public)
CHURCH（僅當 memberships/{uid}.status==active 時發出，churchId = 該 active church）:
  study_content.where(status==published).where(audience==church)
              .where(allowed_church_ids array-contains <churchId>)
INTERNAL: 不發 query（rules 亦 deny）
```
- `list` = union(PUBLIC, CHURCH)。
- `byTopic` / `byContentType` = 各在上兩條再加 `.where(topic_ids array-contains t)` /
  `.where(content_type==x)`。
- `byId` = `get(study_content/{id})`；rules 逐 doc 驗 audience 授權；repo 再驗一次回 null-if-unauthorized。
- 完全可由 Firestore client query + Rules 安全表達（結構化讀取）。**Search / 全文** 不行 →
  見 §12：必須先組 Authorized Universe 再 client 端文字比對，或走 trusted service。

Topic / Annotation / Teacher Book / Chapter 的 Student 讀取套用**相同三段式**（public / church-authorized / deny）。

---

## 9. Topic authorization（定案）

**決策：Option A — Topic 自帶 `audience` + `allowed_church_ids`（與 Study Content 對稱）。**
- 理由：Topic title 可能是 church-specific taxonomy，本身即需授權；對稱契約 rules 一致、
  避免跨 church 計數洩漏。
- Student「主題」清單＝ authorized topics query（§8 同型）。
- **count 洩漏防護**：主題顯示的內容數 = 對該 topic 跑 authorized `byTopic` query 的結果長度
  （**never 讀 stored raw count**）。internal / 未授權 church 的 topic 不進 Student universe。

---

## 10. Annotation domain（定案）

**決策：Option B — annotation 維持獨立 domain，但用相同 managed-content + audience envelope。**
- 理由：註解是 scripture-anchored、Reader 逐節消費，讀取型態與 study_content 瀏覽不同；
  不塞進 study_content contentType，避免污染，也不建新 CMS（重用既有 `annotations` 工作流）。
- `annotations/{id}` 擴充：`scripture_ref`（identity）＋ `body` ＋ `audience` ＋ `allowed_church_ids`
  ＋既有 status/version/provenance。
- Student read：`published && audience 授權`；Reader **只消費 authorized annotations**（core 不改，
  僅 annotation presentation extension）。
- **bundled asset annotation 永遠視為 public**，不得承載 church-private；不回退 assets 承載私有。

---

## 11. Teacher Book / Chapter contract（定案）

- Path：`teacher_books/{bookId}`、`teacher_books/{bookId}/chapters/{chapterId}`（§2.4）。
- Book / Chapter **自身也帶 audience + allowed_church_ids**，Student 讀取 authorization-aware。
- 合法組合：Public Book 底下有 Church Chapter/Teaching → Book 可見，但 Student 只拿到自己
  **authorized** 的 chapters；chapter 的 teaching 數 = authorized study_content query 長度。
- **Metadata leakage 防護**：Book title / Chapter title / teaching count / 私有結構存在性，
  一律經 audience 授權過濾；未授權者對該 Book/Chapter 之存在**不可知**（query 不回、byId deny）。

---

## 12. Teaching linkage & Search boundary

- **Teaching linkage**：`study_content.teacher_book_id` + `study_content.teacher_chapter_id`
  （reference 在 study_content 上）。Chapter 的 teachings = authorized
  `study_content.where(teacher_chapter_id==X)` ＋三段式 audience 授權。
- **Search R1 boundary（定案，最小安全）**：
  - Bible 全文＝本地 in-memory（公開文字，安全，維持現狀）。
  - Study Content / Teacher teaching＝**先組 Authorized Universe（§8 的 authorized queries）→
    client 端 textual 比對**。unauthorized doc **從未被 fetch**，故不進 count/title/preview/
    autocomplete/suggestion/recent。
  - Q&A retrieval＝維持既有 human-curated / Published-only；若答案引用 church 內容，
    citation 顯示與開啟走 §13 open-time 授權。
  - 未來若要伺服器端全文＋授權，再引 trusted search index（Phase 2）。

---

## 13. Q&A source authorization contract

- **`AnswerSource` 擴充**（沿用既有 model，加語意）：`access ∈ public|church|internal`；
  church source 另存 `scope` 快照（可含 allowed_church_ids 摘要）**僅供顯示，非 authority**。
- **Admin picker / publish validation**：picker 只列 `status==published`（既有）；發佈前
  re-validate 每個 study_content source 仍 published（既有），並 snapshot 其 audience/access。
- **Student open-time resolution**：點開一律走 authorization-aware study_content repo
  （public 或 authorized church）重新解析：
  - Active authorized → clickable → detail。
  - Revoked / 未授權 church / internal → **顯示安全 title snapshot（evidence）＋「目前無法存取」**，
    no excerpt / no body / no deep-link。
  - never-authorized other church → 同「無法存取」呈現（title snapshot only），不進可開啟 universe。

---

## 14. Saved Study Content（已 RATIFY）

`users/{uid}/saved_study_content/{contentId}` ＝ `{content_id, saved_at}`，只存 relationship。
Open：由 contentId → authorization-aware repo **live resolve**；授權→開，未授權/revoked→
不回 private payload、顯示「目前無法存取」、relationship 可保留或由 User 刪。
Membership revoke **不自動刪** saved relationship。技術命名可依 repo 慣例調整，semantics 不變。

---

## 15. Offline（已 RATIFY）

- Public 內容：依既有 cache policy。
- **Church-private：R1 不提供 offline**；開啟必須能確認「目前」Active Membership 授權；
  offline 或 authorization unknown → unauthorized。
- 不得以 lastKnownChurchId / lastKnownActive / saved relationship / cached authorization snapshot
  當有效授權。R1 **不新增** membership/authorization revision / revoke marker（那是 Phase 2）。
- **Logout / account switch**：church-private payload 不得被下一個 account / guest 取用
  （切帳號即清 in-memory church-private cache）。

---

## 16. Firestore Rules matrix

Helpers（新增）：
```
isSignedIn(), isAdmin()                                   // 既有
activeChurchId() = get(/databases/$(db)/documents/memberships/$(uid)).data.church_id
                   當且僅當該 doc.status=='active'，否則視為無
isPub()      = resource.data.status=='published'
audienceOK() = resource.data.audience=='public'
             || (resource.data.audience=='church'
                 && resource.data.allowed_church_ids is list
                 && resource.data.allowed_church_ids.hasAny([activeChurchId()]))
             // audience 缺失 / 'internal' / church 但無授權 → 全 false（fail-closed）
```

| collection | Student read | write |
|---|---|---|
| `churches/{id}` | `resource.data.active==true` 或 isAdmin() | isAdmin() |
| `churches/{id}/private/capabilities` | 本人 `activeChurchId()==id` 且 parent Church active；否則 deny | isAdmin() |
| `churches/{id}/private/{other}` | **deny** | isAdmin() |
| `memberships/{uid}` | `request.auth.uid==uid` 或 isAdmin() | **create**：本人且 `status=='pending'` 且未設 reviewed/rejected/revoked 且 target church `active==true`；**update/delete（approve/reject/revoke/set active/church）**：isAdmin() |
| `memberships/{uid}/history/**` | **deny** | isAdmin() |
| `study_content/{id}` | `(isPub() && audienceOK())` 或 isAdmin() | isAdmin() |
| `study_topics/{id}` | 同上 | isAdmin() |
| `annotations/{id}` | 同上 | isAdmin() |
| `teacher_books/{id}` | 同上 | isAdmin() |
| `teacher_books/{id}/chapters/{cid}` | 同上 | isAdmin() |
| `*_workspace/**`, `*/versions/**` | **deny**（admin-only） | isAdmin() |
| `users/{uid}/saved_study_content/**` | owner | owner |

**Rules-are-not-filters 配合**：church list query **必須**自帶
`where(audience==church).where(allowed_church_ids array-contains <myChurchId>)`；rules 逐 doc
以 `audienceOK()` 驗，query 未加述詞或帶他 church id → 有 doc 不符 → 整個 query 失敗。故 client
只能查自己授權的子集（正確的安全結果）。**Inactive church**：`activeChurchId()` 只在 status active
時有值；且 membership create 要求 target `active==true` → inactive 不能成為新 request/authority。
audience==church 且 `allowed_church_ids` 空 → `hasAny` 為 false → deny（且 Admin 端 §3 禁送審/發佈）。

---

## 17. Required composite indexes（只列 R1 query 真需）

`study_content`：
- `status ASC, audience ASC`
- `status ASC, audience ASC, allowed_church_ids ARRAY`
- `status ASC, audience ASC, content_type ASC`
- `status ASC, audience ASC, topic_ids ARRAY`
- `status ASC, audience ASC, teacher_chapter_id ASC`（chapter→teachings）
- church 變體（加 `allowed_church_ids ARRAY`）：與上列同前綴 + array-contains 需各自複合
  （Firestore array-contains 每 query 一個）：
  - `status, audience, allowed_church_ids(array), content_type`
  - `status, audience, allowed_church_ids(array), topic_ids(array)` → **不可**（單 query 至多一個
    array field）→ church + topic 需以 topic 為 array、church id 以等值 fan-out（見下註）。
- **註**：Firestore 單 query 只允許一個 array-contains。church+topic 同時篩選時，
  以 `topic_ids array-contains` 為主、`allowed_church_ids` 改為對「該使用者單一 activeChurchId」的
  等值化處理：新增反正規化欄位 `church_scope`（見實作註）或以 topic query 後 client 端再驗
  audience 授權。**R1 建議**：church+topic 走「topic query（authorized universe）→ client 驗
  audience」以免 index 爆炸。

`study_topics`：`status, audience`；`status, audience, allowed_church_ids(array)`。
`annotations`：`status, audience, scripture_ref`；church 變體加 array。
`teacher_books`：`status, audience`（＋ order 排序時加 `order`）。
`teacher_books/*/chapters`（collection group 若跨書查詢）：`status, audience, order`。
`memberships`（Admin views）：`status`（列 pending/active）；`church_id, status`（某教會成員）。

不為 Phase 2 假想 query 預建。

---

## 18. Firestore Rules（部署順序內含 migration 依賴）

見 §7：**migration 補 audience → deploy indexes（等 Ready）→ deploy rules**。順序錯會 fail-closed
隱藏 legacy 內容或 query 缺 index。

---

## 19. Migration strategy（本輪不寫、不執行）

- **範圍**：為既有 `study_content` / `study_topics` 補 `audience`（§7 映射）；為既有 cloud
  `annotations` 補 `audience=public`（原本即公開）。teacher/membership/churches 無 legacy。
- **性質**：additive、deterministic、dry-run 預設、fail-closed（未知值 → internal）、idempotent
  （skip 已有 audience 者）、輸出 summary、不刪任何 legacy、visibility 保留不動。
- **exposure 不擴大**：只把「原本已 student 可見」→ public；internal 維持 internal；不確定 → internal。
  **絕不**自動產生 church / 自動填 allowed_church_ids。
- **rollback**：audience 為 additive 欄位；回滾 = 還原舊 rules（讀 visibility）即可，或忽略 audience。
  保留 legacy compatibility window：舊 rules 與新 rules 不同時生效，切換點即 rules deploy。
- 工具沿用 `tools/` fail-closed 模式（偵測 emulator/缺 creds 即中止；`--apply` 才寫）。

---

## 20. Implementation order（交給 Codex 的建議順序）

1. **Domain models + enums**：`Audience`、`Membership`、`Church`、`teacher_books/chapters`、
   `SavedStudyContent`；`ManagedContent` 加 `audience/allowedChurchIds`（reservedKeys 同步）。
2. **Repository/service**：`MembershipRepository`（self-read＋create pending）、`ChurchRepository`
   （active picker）、`StudyContentRepository` 擴充 Authorized Universe（§8）＋ annotation/teacher
   authorized reads、`SavedStudyContentRepository`。全部「query 自帶授權述詞」。
3. **firestore.rules**：§16 matrix。**tests（emulator）**：public/church/internal × active/none/
   revoked/other-church × list/byId/workspace/versions；membership self-read/create/admin；
   churches public/private split；teacher/annotation 授權；saved owner-only。
4. **firestore.indexes.json**：§17。
5. **Admin**（既有 workflow 上加 audience 選擇＋church picker＋empty allowedChurchIds 阻擋＋
   expansion warnings；membership requests list/approve/reject/revoke；teacher book/chapter CRUD）。
6. **Student**（Me→教會、Bible→老師專區、authorized 研讀內容/主題/annotation、Q&A open-time
   授權、Saved live-resolve）。Reader core 不改。
7. **migration tool**（dry-run）。
8. **Dart/rules tests** 全綠 → 交付。

（§5–6 model 定案後，1–4 可直接開工；5–6 UI 依既有 Admin/Student IA，不重新設計。）

---

## 21. Production rollout dependencies

1. 先合併 backend 契約實作（models/repo/rules/indexes/tests），**不 deploy**。
2. **migration dry-run**（production 唯讀）確認 audience 映射 summary（public/internal 數、
   未知→internal 數、church 數必為 0）。
3. **migration apply**（補 audience）。
4. deploy `firestore.indexes.json` → 等所有新 index Ready。
5. deploy `firestore.rules`（audience authority 生效）。
6. deploy Admin（管理員先能設 audience/church、審核 membership）。
7. Admin 逐項決定 church/public、建立 churches、審核 membership。
8. **最後**才 deploy Student（新授權 UI）。
   —— 順序不可反（§7）。Render 兩服務共用 branch，deploy 需逐服務手動、避免 Student 提前上線。

---

## 22. Unresolved blockers（需一句話確認，非重新設計）

- **B1（membership 模型）**：接受 `memberships/{uid}`（doc-id=uid）＝「一人一 membership 記錄、
  換教會需先 revoke」？（R1 建議 yes；否則改 requests+active-pointer 模型。）
- **B2（Topic 授權）**：接受 §9 Option A（Topic 自帶 audience）？（建議 yes。）
- **B3（trusted layer）**：R1 無 Cloud Functions；所有授權靠 Firestore Rules ＋ Admin-authoritative
  `memberships/{uid}`。確認 R1 不需要伺服器端 trusted enforcement（search 走 authorized-universe
  client 比對）。若未來要伺服器端全文授權搜尋，Phase 2 再引 trusted search。
- 以上三點皆為「接受既定預設 or 指定替代」，不含新產品決策。

---

## 是否足夠直接交給 Codex 實作？

**是**——§1–§21 已把 collections / schema / enums / references / authority / invariant /
public-private split / audience 演進 / query 契約 / topic / annotation / teacher / linkage /
saved / offline / Q&A source / search boundary / rules matrix / indexes / migration / 實作順序 /
rollout 全部落定，且與既有 workflow/repository/AnswerSource/owner-rule 對齊、fail-closed 一致。
唯一開工前需你一句話確認的是 §22 的 B1–B3（採預設或指定替代），其餘無 open question。
⛔ 內容文字仍由使用者親撰；本契約只定資料/授權/格式。
