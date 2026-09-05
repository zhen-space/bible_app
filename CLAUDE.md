# 聖經 App — 傳承文件

每次新 session 先讀這份文件。每次大改動後更新它。

## ⛔ 內容守則（使用者明令，不可違反）

**註釋、導讀等所有註解「內容」由使用者本人親自撰寫。Claude 一律不准新增、修改、生成或代填 `assets/annotations/annotations.json` 裡的文字內容。**
- 可以做：改「程式/UI/資料格式/顯示方式」、修 bug、加欄位。
- 不可以做：寫任何導讀、注釋、關鍵字、生活應用、重點等文字。
- 目前檔案裡只留創1（早期 Claude 產的範例，詩23/約3 已依使用者要求刪除），保留當**格式範本**即可；使用者要換成自己寫的內容。若使用者要求清空範例，才可刪。

## 專案概況

Flutter 聖經 App，**和合本神版**（繁體）離線讀經。功能：引導式首頁、讀經（**兩種閱讀模式**：逐節分行／整章連續）、**中英對照**（KJV，每節中文下接英文）、**聽聖經**（TTS 逐節朗讀，朗讀中的節即時高亮）、卷導讀（獨立方格）＋卷統整（整卷最後一章末）、每節註解（注釋/關鍵字/生活應用/交叉引用可跳轉）、讀經頁內建搜尋、全文搜尋（含模糊/子序列）、節位快速跳轉（約3:16）、搜尋歷史、主題閱讀（含**主題導讀**欄位）、**讀經計畫**（一年通讀/90天速讀/新約，逐日勾選進度）、人生情境入口、每日經文、讀經進度、**我的信仰地圖**（66 卷依已讀比例上色）、首頁個人筆記、**禱告事項**（分類/子分類/內容，位置可選）、**信仰生活代辦**（分類/內容/可打勾）、書籤、螢光筆（5 色，**可命名**）、經節筆記（含觀察/相信/行動三欄模板、標籤）、**主日證道筆記**（結構化：主題/日期/經文/筆記/祂的話/實踐/感想，可**匯出**複製或下載 .md、可**匯入**檔案或貼上文字）、統計小卡、筆記匯出（Markdown 複製／HTML 下載可存 PDF/用 Word 開）、深淺色主題、字級調整、記住閱讀位置。

- 配色（使用者要 Apple 風、不要像 Google）：淺色＝天空藍底（`_skyBg`）＋白圓角卡片＋**金圖標**＋黑字；深色＝深藍底＋白字＋金圖標。圖標色靠 `iconTheme`/`appBarTheme.actionsIconTheme`/`listTileTheme` 統一設金。iOS 感：大標題（左對齊粗體）、Card 圓角 18、elevation 0。見 `theme/app_theme.dart`。
- 登入：Google（已通）＋ Apple（`OAuthProvider('apple.com')` popup；需 Firebase 啟用 Apple provider、Apple Developer 建 Service ID 才會動）。
- **章層級導讀/重點已移除**（使用者要求）：讀經頁不顯示章導讀卡；導讀＝卷層級（books 頁「導讀」方格），統整＝卷層級（整卷最後一章末的「本卷統整」卡 + 「統整」方格）。
- 英文 KJV：`assets/bible/kjv.json`（4.5MB，公有領域），只在需要時（進讀經頁或開對照）載入；節數與和合本差 4 節，對不到的節不顯示英文。

- 聽聖經：`flutter_tts`（網頁走瀏覽器 SpeechSynthesis、手機走系統 TTS），`services/tts_service.dart` 逐節朗讀、追蹤目前節號供高亮；換章/離開頁自動停。
- 狀態管理：Riverpod（`flutter_riverpod`，Notifier/FutureProvider）
- 使用者資料：sqflite（存書籤/螢光筆/筆記/讀經紀錄/證道筆記/讀經計畫進度/禱告事項/代辦事項/刪除墓碑；**經文不進 DB**）
- 經文來源：`assets/bible/cuv.json`（約 3.3MB，66 卷 31,104 節），啟動時載入記憶體，搜尋直接掃記憶體
- 設定持久化：shared_preferences（主題、字級、閱讀位置含節、螢光筆命名、禱告位置）
- Firebase：**已接（Web 先行）**。專案 `bible-app-c0eac`；`lib/firebase_options.dart` 只有 web 設定（iOS/Android 之後在 Mac 跑 `flutterfire configure` 覆蓋該檔）。Google 登入（popup）＋ Firestore 雲端備份：`services/sync_service.dart` 多表雙向 LWW 合併（bookmarks/highlights/notes/reading_log/sermon_notes/plan_progress/prayers/todos→`users/{uid}/...`）。**已支援同步刪除（tombstone）**：`tombstones` 表記錄刪除，不變量＝同一筆資料「活資料」與「墓碑」互斥（刪除寫墓碑、新增/更新清墓碑）；sync 先合併墓碑→下載擋掉被刪→套用墓碑刪本地→上傳墓碑並刪雲端 doc。main() 裡 init 失敗不擋 App；未登入一切照常。**新資料表記得加進 sync service，刪除要記墓碑**。
  - **網頁 Firestore 強制 long-polling**：`main.dart`/`main_admin.dart` init 後設 `FirebaseFirestore.instance.settings = Settings(persistenceEnabled:false, webExperimentalForceLongPolling:true)`。預設 WebChannel 在部分瀏覽器/網路會默默卡死（`.get()` 不回也不報錯，同步停在「同步中…」），long-polling 幾乎所有環境都通。**設定必須在任何 Firestore 呼叫前套用**（放 runApp 前）。
  - **⚠️ 已實機驗證通過（登入＋雲端同步＋刪除同步）**，但有瀏覽器層限制：**Mac Safari 對 Firestore 長連線不友善會卡**（換 Chrome 正常）；**iOS Safari 需關「防止跨網站追蹤」**登入才過（ITP 擋 GIS 跨站憑證回傳）。部署站 COOP 必須是 `same-origin-allow-popups`（見下 render.yaml 段），否則登入彈窗空白。

## 目錄結構

**雙 app 架構**：同一 repo、共用 models/services/providers，兩個進入點：
- `lib/main.dart`：讀經 app（一般使用者）。**不含**任何管理 UI，只讀雲端內容。
- `lib/main_admin.dart`：內容後台 app（管理者），`AdminGate` 登入後只有 kAdminEmail 進得去，
  含導讀/註解編輯、公開註解審核、Q&A 審核回答、知識架構編輯。獨立 build／部署
  （`render-build-admin.sh` → `build/web-admin`，render.yaml 第二個服務 `bible-app-admin`）。

```
lib/
  main.dart                 讀經 app 入口，ProviderScope + MaterialApp
  main_admin.dart           內容後台 app 入口（獨立部署）
  models/models.dart        Book/VerseRef/Bookmark/Highlight/Note
  data/topics.dart          主題/情境精選經文（節位字串，有測試守著有效性）
  services/
    database_service.dart   SQLite（含升版框架，見下；目前 v8）
    bible_repository.dart   經文載入與搜尋（含模糊/子序列）
    verse_locator.dart      節位解析（「約3:16」→ bookId/章/節）
    annotation_repository.dart  註解內容載入（章導讀/節註解，可插拔）
    tts_service.dart        聽聖經（flutter_tts 逐節朗讀）
    qa_service.dart         疑問 Q&A（全人工，Firestore questions）
    knowledge_repository.dart  知識架構載入（時間軸/人物/平行/預表，asset）
    download_web.dart / download_stub.dart  瀏覽器檔案下載（條件式 import）
  data/topics.dart          主題＋主題導讀（Topic.intro）
  data/reading_plans.dart   讀經計畫（機械排程，非撰寫內容）
  providers/providers.dart  所有 Riverpod providers
  theme/app_theme.dart      深淺色主題 + 螢光筆顏色
  screens/                  home / chapter / search / bookmarks / settings / topics /
                            book_overview / faith_map（信仰地圖）/ reading_plans（讀經計畫）/
                            sermon_notes（證道筆記）/ qa（疑問 Q&A）
assets/bible/cuv.json       和合本經文（見「經文資料」）
assets/annotations/annotations.json  註解內容（見「註解內容模組」）
```

## 註解內容模組（白板二）

- 資料在 `assets/annotations/annotations.json`，**內容可插拔、可缺**（缺就不顯示，不擋讀經）。
- key 格式：
  - `books['書卷id']`：**整卷導讀＋統整**（獨立標籤方格，見下），格式 `{ intro:{summary,purpose,author,background}, outline:[...], summary:'統整文字' }`
  - `書卷id:章`：章導讀（大意/目的/作者/背景/分段/重點）
  - `書卷id:章:節`：節註解（注釋/關鍵字/**background 背景**/生活應用/交叉引用）
- **讀經頁節面板＝抽屜＋Tabs**（字義/背景/應用/相關）：快速動作（螢光筆/書籤/筆記/複製/投稿）在上，深度註釋收 Tabs，保持閱讀主體乾淨。
- **雲端註解版本化**：`content_service._setVersioned` 存檔時把舊內容快照進 doc 的 `versions` 陣列並蓋 `updated_at`；讀者端節面板顯示「註解更新於…」。
- **混合快取**：雲端 annotations/knowledge 抓到就存 SharedPreferences（`cache_annotations`/`cache_knowledge`），離線退回上次快取，再退 asset。
  - 書卷 id：創=1、詩=19、太=40、約=43。
- **導讀／統整標籤方格**：書卷章節格最前面固定一個「導讀」方格、最後面一個「統整」方格（`_OverviewBox`），開 `BookOverviewScreen`。方格永遠在；沒內容時顯示待填空白頁（不代寫內容）。
- 交叉引用（crossRefs）是節位字串，讀經頁點了會跳轉；可帶範圍（約1:1-3），跳轉時取破折號前。
- 目前只留 1 章示範內容（創1，使用者要求刪掉詩23/約3）。創1 可在後台編輯。**補內容 = 後台撰寫或編輯這個 JSON**，不用改程式。
- 章導讀「分段」欄（outline，如「1-8 各支派在營地的位置」）會解析成經文中的**段落標題**（`headingsFromOutline`）。
- 有測試守著：所有 key 在範圍內、所有交叉引用能解析。
- **管理後台（App 內）**：管理者（`kAdminEmail`＝使用者本人）登入後，設定頁出現「內容管理」。可在 App 內撰寫卷導讀/統整、章導讀/重點、節註解，存 Firestore `annotations` collection（doc id：`book_{id}` / `chapter_{id}_{章}` / `verse_{id}_{章}_{節}`，資料形狀同 asset JSON）。讀經端 `cloudAnnotationsProvider` 啟動抓一次，**雲端優先、asset 為底**合併。⛔ 內容仍由使用者親寫，Claude 只維護編輯器。
- **公開註解投稿＋審核**（白板「每句可個人註解但公開須經審核」）：登入者可在讀經頁對經節「投稿公開註解」→ Firestore `submissions`（status pending）。管理者在後台「公開註解審核」佇列 approve/reject；通過會複製到 `public_notes`（所有人可讀），讀經頁經節選單顯示「社群註解」。用 `loc='書卷id_章'` 單欄位查詢，免複合索引。⛔ 這是使用者投稿內容，非 Claude 代寫。

## 知識架構模組（白板七，內容⛔使用者親寫）

- 資料在 `assets/knowledge/knowledge.json`，預設全空；`models/knowledge.dart` 定義格式、
  `services/knowledge_repository.dart` 載入、`screens/knowledge_screen.dart` 顯示。
  缺內容就顯示「待補」空狀態，不擋任何功能。首頁「聖經知識庫」入口。
- **相關經文推薦**沿用既有節註解的 `crossRefs`（讀經頁點了跳轉），不在此檔。
- 這裡涵蓋另 4 類（各是一個陣列，節位字串都可點跳讀經頁）：
  - `parallels`：平行經文對照 `{ title, refs:[節位…] }`
  - `types`：舊約預表→新約應驗 `{ title, otRef, ntRef, note }`
  - `timeline`：聖經時間軸／事件線 `{ order, era, title, when, ref }`
    （`order` 小到大排、`era` 分期分組、`when` 是年代**文字**因年代有爭議）
  - `people`：人物 `{ id, name, aka:[], bio, events:[{title,ref}],
    relations:[{type, personId, name}] }`；relations 的 personId 指到別人 → 詳情頁可跳過去
- ⛔ 內容（哪些經文平行、預表對應、年代、生平、關係）一律使用者親寫；Claude 只維護格式與 UI。
- **雲端編輯**：後台 app 的「知識架構編輯」（`screens/admin_knowledge_screen.dart`）寫入
  Firestore 單一 doc `knowledge/data`（4 個陣列，即讀改寫整份）。讀經端
  `knowledgeProvider` **雲端優先、asset 為底**合併（`cloudKnowledgeProvider`）。
- 有測試守著格式解析（合成資料，非聖經內容）。

## 疑問 Q&A 模組（白板六，**全人工、無 AI**）

- `services/qa_service.dart` + `screens/qa_screen.dart` + `providers` 一組。Firestore：
  - `questions/{qid}`：問題本體（uid/author/title/body/category/status/featured/時間）＋
    `answer`（content/scriptures/tags/時間）＋ `answer_versions`（回答更新紀錄，arrayUnion 舊版）
  - `users/{uid}/following/{qid}`：追蹤（存 seen_at，做「有新回答」未讀提示）
  - `users/{uid}/saved_questions/{qid}`：收藏
- 分類：`kQaCategories = [神學, 生活, 爭議, 其他]`。列表查詢都用**單一欄位**（status 或 uid），排序/搜尋在用戶端做（免複合索引）。
- **語音提問**（`qa_screen` 右上麥克風 → `qa_voice_screen.dart`）：`speech_to_text`（zh_TW）
  轉文字 → 先列「現有解答」（**純關鍵字比對**已公開 Q&A，無 AI）→
  「不滿意？送出等教會回答」→ 進 pending 佇列。
- 流程：使用者提問→`pending`→管理者（kAdminEmail）在 Q&A 頁審核/親自回答（回答即 `approved` 公開）。回答可引用經文（節位字串，點了跳讀經頁）、加標籤、精選置頂、編輯（保留更新紀錄）。
- ⛔ **問題與回答都是人寫的內容**（提問者/管理者本人），Claude 只維護程式與編輯器，不代寫問答文字。
- 未做：真推播（需 FCM）——目前「通知」是 App 內未讀紅點（`followingQuestionsProvider` 比對 answer.updatedAt vs seen_at）。
- Firestore 規則見 `firestore.rules` 的 `questions` 區塊；following/saved 走 `users/{uid}` 萬用規則。

## 經文資料

- 來源：scrollmapper/bible_databases 的 `ChiUn.json`（和合本繁體，公有領域）
- 轉檔：清掉斷詞用的 ASCII 空格、保留「　神」前的全形空格（敬虔空格）、套 66 卷中文書名
- 格式：`{translation, translationId, books: [{id, name, abbr, testament, chapters: [[經文…]]}]}`
- `chapters[章-1][節-1]` 取經文，book id 1–66

## DB 升版規則（兩邊都要寫！）

`database_service.dart`，目前 **v14**（v2 reading_log；v3 notes.tags；v4 sermon_notes；v5 plan_progress；v6 tombstones；v7 prayers；v8 todos；**v9 chapter_completions**；**v10 plan_item_progress**；**v11 later**；**v12 notes.title/refs/deleted_at**；**v13 prayers v2 欄位**；**v14 plan_item_progress.item_id**；**v15 plan_item_progress.plan_version**）。升版時：
1. `_dbVersion` +1
2. `_onUpgrade` 加 `if (oldV < n)` 區塊
3. `_createAllTables` 同步加建表語句（全新安裝走這裡）

另外：`HighlightColor` enum 以 index 存 DB，**順序不能改**，只能往後加（有測試守著）。

## 架構備忘（新增）

- **自動備份（Auto-Sync）**：`DatabaseService.onMutate` 在每個寫入方法尾端觸發；
  `SyncStatusNotifier.build()` 掛上 debounce 10 秒的 `syncNow()`（登入時才動）。
  **新增寫入方法記得呼叫 `_mutated()`**。`syncAll` 各階段（讀取刪除紀錄／下載／
  上傳／寫入雲端）以 `onStep` 回報進度到狀態列；`syncNow` 有 45 秒逾時（卡住會停在
  該步驟並轉明確失敗訊息，不再永遠轉圈）——診斷同步卡點就靠這行狀態字。
- **原子化跳轉**：`services/app_links.dart`（`AppLinks.openVerseRef`/`openPerson`）。
  各模組（Q&A 引用、知識庫、搜尋人物→生平頁）一律走這裡，勿自寫跳轉。
- **長章渲染＋記住位置**：逐節模式用 `ListView.builder` 懶載入（詩119 176 節不卡）。
  記住位置走 `ScrollController` 位移：`lastRead` 存 book:chapter:**offset**，捲動時
  debounce 存 offset，「繼續閱讀」用 initialOffset 還原捲動位置（首屏後 jumpTo）。
  ⚠️ 曾試 `scrollable_positioned_list` 但在 iOS Safari 首屏渲染空白（民數記17 實測），已移除。
- **語音**：輸入用 `speech_to_text`、輸出用 `flutter_tts`，皆 zh-TW。
- **私名號（專名號）＋名字最長匹配**：`data/entities.dart` 的 `properNames`（人名＋地名，
  含別名，事件不算）＋ `properNameMatches`（最長優先，「以利亞撒」不會被「以利亞」切開）。
  `utils/text_utils.dart` 的 `properNameSpans` 把名字畫底線（讀經頁逐節/段落模式、搜尋結果都套）。
  搜尋用 `queryOnlyInsideLongerName` 濾掉誤配（搜「以利亞」不列只有「以利亞撒」的節）。
  **覆蓋＝索引涵蓋的名字**（目前約 40+，未收錄者不標／不斷界）；擴大覆蓋＝增補 `entities`。
  ⛔ 名字索引屬「資料」（非導讀/註釋內容），AI 可維護，但增補人名地名前仍宜與使用者確認。
- **證道筆記匯入／匯出**：`services/sermon_notes_io.dart`（`sermonNotesToText`／
  `parseSermonNotes`）＝可來回轉換的 Markdown（每則 `## 標題`＋`#### 主題/日期/
  經文/筆記/祂的話/實踐/感想` 小標，`---` 分隔）。檔案存取走 `download_web`/
  `download_stub` 條件式 import（`downloadTextFile`／`pickTextFile`／`canPickFile`；
  手機無選檔→貼上文字）。⛔ 只做格式轉換，不代寫內容。
  （備註：model 仍留 `trinity_who` 欄位供舊資料相容，但編輯頁與匯入匯出已不再使用。）

## P0 前台改版（本輪 #1b–#7，branch `agent/p0-reading-foundation`）

三種閱讀概念**正式分離**（#1b）：**Reading History**＝`reading_log`（造訪，開章即記，臨時瀏覽不記）；**Reading Position**＝`lastReadProvider`（繼續閱讀，SharedPreferences）；**Chapter Completion**＝`chapter_completions`（v9，使用者主動按讀經頁「完成本章」才算）。**打開章節≠完成章節**。信仰地圖／已讀統計改用 completions（升版時由 reading_log 種入，保留舊進度）。

- **Reading Plans v2**（#2）：`plan_item_progress`（v10）逐「讀經項目（章）」勾選；今日進度（第一個未完成的天）vs 整體進度分離；漏讀保留並標記；舊 `plan_progress`（整天）保留相容，開啟計畫時一次性 lazy 種入 item 進度。官方 Published 計畫內容需後端（未做）。
- **Daily Verse v2**（#3）：正式來源＝Firestore `daily_verses/{YYYY-MM-DD}`（`published==true`，`ContentService.fetchPublishedDailyVerse`＋`publishedDailyVerseProvider`，快取 SharedPreferences）；`dailyVersePool` 降為 fallback。發佈 UI 需後台（未做）。
- **Verse Actions v2**（#4）：`later` 表（v11，稍後閱讀）；讀經頁**逐節模式多選**（長按選取、批次螢光筆/書籤/稍後讀/複製/分享）；複製/分享分「純經文／經文＋出處」（`utils/share_utils.dart`）。共用單節面板 `screens/verse_action_sheet.dart`（每日經文等非讀經頁入口用）。
- **Notes v2**（#5）：`notes` 加 `title`/`refs`/`deleted_at`（v12）；可選標題、多節引用、軟刪除（最近刪除，還原/永久刪除）；`screens/notes_screen.dart`（最近/書卷/標籤/搜尋＋編輯器自動儲存＋引用點開臨時閱讀）。逐節快速筆記 `saveNote` 不動 title/refs。
- **My Content**（#6）：`screens/my_content_screen.dart` 統一入口（經文筆記/螢光筆/書籤/稍後閱讀/證道筆記/禱告，各自獨立 model）；`LaterScreen` 待讀清單。App shell「筆記」tab 改為「內容」→ MyContentScreen（`notes_hub_screen.dart` 退出導航，未刪）。
- **Prayer v2**（#7）：`prayers` 加 title/prayer_date/refs/status(praying/answered/ended)/reminder_at/answered_at/answered_reflection（v13）；舊 category/subcategory/content 保留相容。提醒只存時間（真推播需 FCM，未接）。
- **同步/墓碑**：新增 tombstone kind `completion`、`later`；`chapter_completions`/`plan_item_progress`/`later` 都進 `sync_service`（LWW）。notes 軟刪除是**本地 trash**（purge 才寫墓碑同步刪除）。plan 進度沿用舊慣例（取消＝本地刪除、無墓碑）。
- **#8（Published-only 授權：annotations/knowledge/public_notes 仍 `allow read: if true`、SharedPreferences/asset fallback）與 #9（Q&A 安全）留給「後端 × Codex」**，本輪未動。`firestore.rules` 已加 `daily_verses` 讀規則（**未 deploy**）。

## #8/#9 Published-content workflow ＋ Q&A safety（branch `agent/p0-backend-published-workflow`）

受管理內容（annotations/knowledge/daily_verses/public_notes/reading_plans）改為
**Draft→Review→Published→Rejected/Archived** 工作流：**只有 `status=='published'` 可被學生端取得**，
`firestore.rules` 真正阻擋（不是 UI 隱藏）；workspace（`<type>_workspace`）僅管理員。
版本＋溯源（`content_id/status/version/created/updated/reviewer/publisher/provenance`）；
**新 Draft 不覆蓋 Published version**（草稿寫 workspace，發佈才複製到 mirror＋version+1，
舊快照入 `versions`）。model＝`models/managed_content.dart`，工作流＝`services/content_workflow_service.dart`。

- **fail-closed client**：annotations/knowledge 只讀雲端 Published、快取只存 Published、**移除 asset fallback**；
  每日經文只讀 Published、無 → 空卡（**不 fallback pool/random/AI**）。
- **Q&A**：`retrieveApproved` 只在 Published approved 語料比對，不足→`insufficientApprovedContent`；
  回答存 `sources`（content id+version）；pending question 非 knowledge source。
- **admin 直接發佈**路徑（`ContentService.saveBook/Chapter/Verse/Knowledge`、`approveSubmission`）已 stamp
  `status='published'`＋version＋provenance＋publisher。`public_notes` 依 loc+status 查詢（`firestore.indexes.json` 複合索引）。
- **工具**（`tools/`，Node，**本輪不對 production 執行**）：`audit_published.mjs`（唯讀、fail-closed）、
  `backfill_status.mjs`（additive、預設 dry-run）、`rules_test.mjs`（emulator，18/18 通過）。
  fail-closed＝缺 credentials/偵測 emulator 立即中止，絕不 fallback local。
- ⚠️ **部署順序**：先 backfill 補 status，**再**部署 `firestore.rules`＋`firestore.indexes.json`（本輪未 deploy）。
- 完整契約見 `docs/PUBLISHED_CONTENT_WORKFLOW.md`。⛔ 內容仍由使用者親撰，Claude 只維護格式/UI/工作流/工具。

## Study Content 後端契約（新版「研讀內容」，branch `claude/bible-app-setup-xi8bvd`）

**Published 與 Student-visible 完全分離**：學生可直接讀 ⇔ `status=='published'` **且** `visibility=='student'`。Published+Internal 合法；visibility 缺失／未知一律 **fail-closed**（不可見）；不得由 status／contentType 推導 visibility。這一輪只落「後端契約」，**無 Admin/Student UI、無 migration 執行、無 deploy**。

- **collections**：`study_content/{id}`（published mirror）、`study_content_workspace/{id}`（草稿工作副本，admin-only）、`study_content/{id}/versions/{ver}`（唯讀歷史，admin-only）；`study_topics` 同構。Legacy `knowledge/data` **保留、不再是新版正式來源、不刪不改**。
- **model**：`models/study_content.dart`＝`Visibility`(internal/student，定義於 managed_content.dart，唯一可見度 authority)＋`StudyContentType`(parallel/type/timeline/person/topic_article，未知→null)＋`StudyContentItem`／`StudyTopic`（橋接既有 `ManagedContent` 外殼，新增 `visibility` 欄位；null 時序列化省略、不污染 annotations/knowledge/daily_verses）＋`StudyContentMigration`（legacy→item 確定性映射）。
- **workflow**：**重用** `ContentWorkflowService`（單一 status truth）。新增 `createDraftFromPublished`（Published 不可直接改，一律建新草稿→審核→發佈；改 visibility 亦然）＋ `approveAndPublish(snapshotToSubcollection:true)`（study 用 versions 子集合）。`saveDraft` 新增可選 `visibility`。新建預設 draft/internal。
- **repository**：`services/study_content_repository.dart`。Student 讀取每個查詢都主動帶 `status==published && visibility==student`（by-id 也再驗一次），**絕不 fallback knowledge/data**（沒有就空）。providers：`studentStudyContentProvider`／`…ByType`／`…ByTopic`／`studentTopicsProvider`。
- **rules**（`firestore.rules`）：`isStudentVisible()`＝published&&student 真正阻擋；workspace／versions 子集合 admin-only。**未 deploy**。
- **indexes**（`firestore.indexes.json`）：study_content 加 (status,visibility)、(status,visibility,content_type)、(status,visibility,topic_ids array-contains)；study_topics 加 (status,visibility)。**未 deploy**。
- **migration tool**：`tools/migrate_knowledge.mjs`（dry-run 預設、additive、deterministic FNV-1a-64 id、idempotent skip-if-exists、**visibility 永遠 internal**、fail-closed、不刪 knowledge/data）。id 演算法**必須與 study_content.dart 同步**（有 Dart 跨語言向量測試守著："abc"→e71fa2190541574b）。**本輪不對 production 執行**。
- 測試：`test/study_content_test.dart`（enum fail-closed／visibility 契約／round-trip／migration 確定性）＋ `tools/rules_test.mjs`（study 讀寫全案）。⛔ 內容仍由使用者親撰；Claude 只維護格式/契約/工作流/工具。

## Study Content ADMIN R1（後台 UI，branch `claude/bible-app-setup-xi8bvd`）

在 backend 契約上做的**後台管理 UI**（無 Student cutover、無 migration 執行、無 deploy）。Admin IA＝`admin_dashboard_screen.dart` 的「內容管理」：研讀內容／主題／每日經文／Q&A／Legacy Knowledge。

- **Study Content Admin**（`screens/admin_study_content_screen.dart`）：清單（篩選 status／visibility／型別／來源＋搜尋）；**Status 與 Student visibility 永遠分開的 badge**；新增先選正式 `StudyContentType`（禁自由字串）預設 Draft/Internal；typed editor 依型別欄位（parallel/type/timeline/person/topic_article，payload 以 backend model 為準）；Draft→送審（確認顯示 visibility 含意）；Review 唯讀＋退回/發佈；**發佈確認依 visibility 分「發布並開放學生」/「發布為內部內容」兩種文案與按鈕**；**Published 唯讀→「建立新版草稿」(`createDraftFromPublished`)**，無 published visibility 直接 toggle；版本紀錄唯讀（versions 子集合）；主題 multi-select 只選正式 `study_topics`（學生可見/內部分組＋內部主題掛在學生內容時警示）。
- **Topic Admin**（同檔 `AdminTopicScreen`/`TopicEditor`）：list＋create/edit，slug 建立後不可改，預設 Draft/Internal，同 workflow，Published→新草稿。
- **Legacy Knowledge reposition**（`admin_knowledge_screen.dart`）：改名「Legacy Knowledge」＋頂部「Legacy / Internal」醒目說明（此區不是新版研讀內容入口、儲存只更新 knowledge/data aggregate、不代表任何項目對學生可見）。**未刪除、未改 production data。**
- **Q&A Sources Editor**（`qa_screen.dart`）：回答編輯器新增「回答依據·已發布內容」——picker **只列 status==published** 的 study content（含 internal，UI 標 visibility），可排序/移除，`answer.sources` 真正持久化並重開載回；**發佈前重新驗證**每個 study content source 仍為 published，否則阻止發佈。Q&A safety contract 未改（human-curated/Published-only/no LLM/no Web/insufficient/pending 不入語料）。
- **Daily Verse Admin**（`screens/admin_daily_verse_screen.dart`）：list＋create，走 ContentWorkflowService 型別 `daily_verses`、**contentId=日期** → one-active-per-date 為結構不變量；節位為正式識別（VerseLocator 解析）；Draft→Review→Published＋Archive；替代＝從現行版本建新草稿→發佈（版本+1）；學生顯示＝`ContentService.dailyVerseVisibleToday`（published 且 date==今天，未來不提前、今天無則 fail-closed）。
- 服務層：`StudyContentRepository` 新增 admin 讀取（adminListContent/Topics union workspace+mirror、adminContentVersions、adminListPublishedForSources、isPublishedNow…）；`QaService`/`ContentService` 加**可注入 FirebaseFirestore**（測試用 DI，行為不變）。providers：adminStudyContentList/adminTopicList/adminPublishedSources/adminDailyVerseList/adminEmail。
- 測試：`test/admin_workflow_test.dart`（fake_cloud_firestore，19 案：defaults、visibility、published/internal vs student、Published→新草稿、版本紀錄、Topic、Q&A sources save/load/order、source 失效驗證、daily verse workflow＋one-active-per-date＋fail-closed、Legacy 隔離）。全套 flutter test 88／rules 58／analyze clean／兩 build 通過。dev dep 加 `fake_cloud_firestore`。

## Student Study Content CUTOVER + R1 GAP（branch `claude/bible-app-setup-xi8bvd`）

學生「研讀內容」正式從 legacy `knowledge/data` 切到 `study_content`（**published+student**，無 fallback）。

- **新學生畫面**：`screens/study_content_screen.dart`＝`StudentStudyContentScreen`（依型別分組＋主題入口）／`StudentStudyContentDetail`（依 `StudyContentType` 顯示 typed payload；scriptureRefs／型別內節位一律走 `AppLinks.openVerseRef`＝**臨時 Reader，不覆蓋 Reading Position**）／`StudentTopicsScreen`（`studentTopicsProvider`，依 sortOrder）／`StudentTopicContentScreen`（`studentStudyContentByTopicProvider`）。型別對學生用友善中文（`studyTypeLabel`，不改 wire）。空狀態直接顯示「尚無已發布…」，**絕不 fallback knowledge/data／bundled／random／Q&A／AI**。
- **入口切換**：`bible_hub_screen.dart` 的「研讀內容」改指 `StudentStudyContentScreen`（不再 import/用 `KnowledgeScreen`）；主題在其內。**Bible→研讀內容 不再依賴 `knowledgeProvider`。** legacy `KnowledgeScreen`／`TopicsScreen`／`data/topics.dart` 保留供舊/其他 consumer（search 人物搜尋、admin、orphaned home），未刪。
- **Q&A 回答依據 R1 gap 補齊**：
  - `AnswerSource` 加 `access`（study_content 記 'student'/'internal' 快照）＋`ref`（scripture 節位）＋`isStudentOpenable`。**學生端顯示 internal source 的 title 取自 answer.sources 的公開快照 `evidence`，不讀 internal 文件**；student source 可點→`StudentStudyContentDetail`，internal source 顯示「已審核內容·內部參考」不可點（安全仍靠 rules）。
  - **結構化 Scripture Source**：Admin 回答編輯器以 `VerseLocator` 解析節位（可帶結束節）建立 `kind:'scripture'` sources（取代逗號字串為 authority）；save 同時鏡射節位到 legacy `answer.scriptures`（相容）。學生端經文依據可點→臨時 Reader。舊回答只有 `scriptures` 仍可顯示、開啟編輯器時種入結構化欄位。
  - Q&A safety contract 未改（human-curated／Published-only／no LLM／no Web／insufficient／pending 不入語料／發佈前 re-validate source published）。
- 測試：`test/student_cutover_test.dart`（無 knowledge/data fallback、published+student only、主題→內容過濾、AnswerSource access/ref/isStudentOpenable、Q&A 結構化 sources save/load/order/access、legacy scriptures 相容）。全套 flutter test 95／rules 58／analyze clean／兩 build 通過。**Reader 未動、Daily Verse 未重做、無 migration/deploy。**

## Church / Teacher 授權 FOUNDATION（backend，branch `claude/bible-app-setup-xi8bvd`）

依 `docs/CHURCH_TEACHER_BACKEND_CONTRACT_R1.md` 落 **authorization-first 後端基座**（**本輪只 backend＋rules＋indexes＋migration tool＋security tests；Student/Admin/Teacher/Reader UI 未做；無 migration/deploy**）。

- **新 authority＝`audience`**（`public|church|internal`，`models/managed_content.dart` 的 `Audience`）＋`allowedChurchIds`；Student 可讀 ⇔ `status==published` 且（public，或 church 且 **Active Membership churchId ∈ allowedChurchIds**）。internal／缺 audience／church 但空 allowedChurchIds → **fail-closed**。舊 `visibility` 保留但**不再是 Church 世界的 authority**。純授權函式＝`study_content.dart` 的 `audienceAuthorized(...)`。
- **models**：`ManagedContent` 加 `audience`/`allowedChurchIds`（reservedKeys/_flat 同步，null 省略不污染既有型別）；`StudyContentItem`/`StudyTopic` 加 audience＋`authorizedFor(activeChurchId)`＋teacher reference（`teacherBookId/ChapterId`）；`models/church.dart`（`Church` 公開表示、`Membership` doc-id=uid、`MembershipStatus`、`StudentAuth`）；`models/teacher.dart`（`TeacherBook`/`TeacherChapter`，audience-gated）。
- **repositories**：`StudyContentRepository` 新增 **Authorized Universe**（`fetchAuthorizedStudyContent/ById/ByType/ByTopic/Topics/Teachings`＝public query ∪ my-church query，byType/byTopic 在**已授權 universe** narrow，**絕不 fetch-all-then-hide**、by-id 也再驗）；`church_repository.dart`＝`ChurchRepository`（active churches、membership self-read/request-pending、admin approve/reject/revoke＋history）、`TeacherRepository`（authorized books/chapters）、`SavedStudyContentRepository`（relationship only、open 走 live authorized resolve）。providers：myMembership/myAuth/activeChurches/authorizedStudyContent/authorizedTopics/church/teacher/saved repos。
- **rules**（`firestore.rules`）：`audienceOK()`＋`activeChurchId()`（get `memberships/{uid}` 且 status==active）；study_content/study_topics/teacher_books(+chapters) 學生讀 = `audienceOK()||isAdmin()`；churches read active-only；private 預設 admin-only，唯一例外是 Student 可 direct-get 自己 Active Church 的 `private/capabilities`；`memberships/{uid}` self-read＋本人只能建/改回 pending（target church 須 active、不得 self-approve）、admin 才能 approve/reject/revoke；workspace/versions admin-only。**未 deploy。**
- **indexes**（`firestore.indexes.json`）：study_content/study_topics/teacher_books/chapters 各加 (status,audience)＋(status,audience,allowed_church_ids array-contains)。保留 legacy visibility 索引（UI 尚未 cutover）。**未 deploy。**
- **migration**：`tools/migrate_audience.mjs`（visibility→audience：student→public、internal→internal、missing→internal fail-closed；**絕不自動產生 church、不擴大 exposure**；dry-run 預設、idempotent、fail-closed）。**部署順序硬性：先 migrate audience → deploy indexes（Ready）→ deploy rules**（否則 legacy 內容 fail-closed 隱藏）。**本輪不執行。**
- 測試：`test/church_authorization_test.dart`（19 案：audience 純函式矩陣、Authorized Universe public∪church、by-id/byTopic/byType 不洩漏 church B、Topic Option A、teacher hierarchy、membership doc-id=uid 唯一/pending/active/revoke、saved 不授予 access）＋`tools/rules_test.mjs`（+21 → 79 案：spec 25 的授權矩陣）。flutter test 114／rules 79／analyze clean／兩 build 通過。
- ⛔ 內容仍由使用者親撰。

### Foundation CLOSURE（補完 backend/security 缺口，仍無 UI/deploy）
- **Annotation audience 授權補完**：`ContentService.fetchAuthorizedAnnotations(auth)`＋`annotationAuthorized()`（public ∪ my-church，fail-closed）＋`authorizedAnnotationsProvider`（Reader 未來消費）；`annotations` rule 改 `audienceOK()`；indexes 加 annotations (status,audience)(+array)；`migrate_audience` 納入 annotations（published→public、其餘→internal，不擴大 exposure）。**Reader 未改。**
- **Membership self-switch 封死**：rules 驗 active A 不可 self →pending A/pending B/改 churchId/自我 approve；只有 rejected/revoked 本人可 reapply→pending（target church active）；其餘全走 Admin。rules_test 加 D/E/F/G/H＋B/C reapply。
- **Inactive-Church / empty-allowedChurchIds publish-target**：落在 **trusted service boundary**（`StudyContentRepository._assertChurchPublishable`：audience==church 時 allowedChurchIds 非空且每個 church 存在且 active，否則 submit/publish throw）——不靠 UI；有 unit test。
- **Q&A open-time 無 visibility bypass**：`qa_screen._openStudyContent` 改走 `fetchAuthorizedStudyContentById(id, myAuth)`（audience 授權），移除 visibility-only by-id 開啟路徑。
- 測試：church_authorization_test 26／全套 flutter test 121／rules 91／analyze clean／兩 build 通過。
- **未做（下一輪 UI）**：Bible→老師專區、Reader annotation 呈現、Search 授權整合。**部署順序不變（migrate audience→indexes→rules→Admin→Student）。**

### UI 整合 R1（Student church + Admin audience，branch `claude/bible-app-setup-xi8bvd`）
交付「授權曝光面」最關鍵的 UI slice（無 deploy）：
- **Student**：`me_screen` 加「教會」→ `church_screen.dart`（`ChurchMembershipScreen` 五狀態 none/pending/active/rejected/revoked，前端不得 self-approve/switch/revoke；`ChurchPickerScreen` 只列 active、確認文案「申請加入」非立即授權）。研讀內容/主題**正式 cutover 到 authorized providers**（`authorizedStudyContentProvider`/`authorizedTopicsProvider`/`authorizedStudyContentByTopicProvider`，不再用 legacy visibility universe）；church item 顯示「教會專屬」badge（不暴露 allowedChurchIds）。Saved：Detail 加書籤 toggle（`users/{uid}/saved_study_content`，非 verse Bookmark）＋`SavedStudyContentScreen`（live authorized resolve，revoked→「目前無法存取」＋可移除，不回 cache 全文）＋My Content 入口。Q&A open-path 已走 authorized by-id。
- **Admin**：dashboard 加「教會與教師」→ `admin_church_screen.dart`（Churches list/create/edit/active toggle；Membership Requests approve/reject，doc-id=uid 結構性防第二 active）。Study Content 編輯器**audience 選擇器**（public/church/internal＋active-church multi-picker），audience 為 authoring authority、visibility 由 audience 派生；church+空 church submit 阻擋（UI＋service 雙層）；public 發布 exposure warning。
- 測試：`test/church_admin_test.dart`。flutter test 123／rules 91（未改）／analyze clean／兩 build 通過。
- **UI COMPLETION 已補**（見下）。

### UI COMPLETION（Teacher Area／Search cutover／Reader annotation／Q&A church／Admin Topic audience）
- **Teacher Area（Student）**：`teacher_area_screen.dart`＝TeacherAreaScreen/BookDetail/ChapterScreen；teaching 點擊 reuse StudentStudyContentDetail（不建第二套）。Bible Hub「理解」入口 **conditional**（`teacherEntryVisibleProvider`：Active Membership＋該 Active Church 的 private `teacher_area` capability；不再以 authorized teaching count 推導）。capability=true 且 0 篇內容仍顯示入口＋empty state；其他 Church capability 不可枚舉。church badge。
- **Admin Teacher**：`admin_teacher_screen.dart`＝Books/Chapters CRUD＋order＋audience（public/church/internal，church 只從 Active Churches picker、空 church 阻擋）；**Add Teaching＝建立 Study Content Draft**（帶 teacher_book_id/teacher_chapter_id，走既有 Draft→Review→Published，不建 teacher_teachings CMS）。
- **Reader annotation**：`cloudAnnotationsProvider` 改讀 `fetchAuthorizedAnnotations`（public ∪ my-church）；**只快取 public**（church-private 不落地 → offline 只有 public）。**Reader core 完全未動**（只換資料來源）。
- **Search cutover**：`search_screen.dart` 新增「內容」＝authorized study content（含 teacher teaching）＋Q&A（authorized universe FIRST → 文字比對，church B 永不進 count/title/preview）；**移除 legacy 硬編 topics 與 knowledge person-link**（entities 名稱索引保留）。
- **Q&A church citation**：AnswerSource.access 依 audience 快照（public/church/internal）；student 端 church source **open-time live-resolve**（授權→可點「教會專屬」；否則「目前無法存取」不可點，不 pre-render body）；admin picker 顯示 audience badge。
- **Admin Topic audience**：TopicEditor 改 audience 選擇器＋church picker（同 Study Content；service `_assertChurchPublishable` 已擋 church+空）。
- 測試：church_admin_test 加 teacher。flutter test 124／rules 91／analyze clean／兩 build 通過。
- **仍未做（明確 deferred，皆 foundation fail-closed 保護、無 leak）**：Admin **annotation audience 編輯器**（cloud annotation 授權 rules/migration 已就緒，但無 church annotation 撰寫 UI）、onboarding church step、Saved/annotation 的 **offline vs revoked 文案區分**（目前統一「無法存取」）、logout/account-switch 顯式清 cache 測試、完整 widget-test matrix、Reader 同節 public+church **雙區塊**呈現（annotation 模型為每節單 doc，雙區塊需 schema 擴充——已標記為 contract gap）。

### TEACHER AREA CAPABILITY CONTRACT（獨立 eligibility authority，未 deploy）
- `churches/{churchId}/private/capabilities`：`teacher_area: bool`；缺 doc／缺欄位／錯誤型別皆 false（fail-closed）。此欄只決定入口存在，不取代 Teacher/Study Content audience authorization。
- `ChurchRepository.fetchCapabilitiesForActiveChurch(uid)` 只從本人 authoritative Active Membership 取 church id，並驗 parent Church active；不 scan Church、不 hardcode id/name、不查 teaching count。Admin 寫入走 `saveChurchCapabilities`。
- Rules：Student 只可 direct-get 自己 Active Church 的 capabilities；Active A 不可讀 B，pending/rejected/revoked/no-membership/inactive 全 deny；其餘 private docs 維持 admin-only。
- UI：`teacherEntryVisibleProvider` 改依 capability；capability=true＋0 authorized books 仍顯示入口，`TeacherAreaScreen` 顯示既有 empty state；一般 Bible 功能不受 Church state 影響。
- 驗證：targeted Flutter/contract 36 項、Firestore Rules 119 項、changed-file analyze clean。無 migration、無 deploy、無 production write。

### CLOSURE R1（onboarding／offline-vs-revoked／殘留 gap 正式定位，branch `claude/bible-app-setup-xi8bvd`）
本輪只落**低風險、不動已驗證 Reader** 的收尾，並把 annotation 多 doc 共存精確定位為殘留：
- **Onboarding church step**（`student_home_screen.dart` `_ChurchOnboardingCard`＋`churchOnboardingVisibleProvider`/`churchPromptDismissedProvider`/`dismissChurchPrompt`）：登入且**無 membership**且未 dismiss 才顯示；可「選擇教會」→ `ChurchPickerScreen`，或「稍後再說」→ 寫 SharedPreferences dismiss。**可略過、非阻塞**（provider error/loading → `.value==true` 為 false → 不顯示）。
- **Offline vs revoked 文案區分**（`resolvedSavedStudyContentProvider` 改回 `(id,item,online)`）：`item!=null`→可開；`item==null&&online`→**revoked/未授權**「目前無法存取」；`item==null&&!online`→**無法驗證**「目前無法驗證教會存取權」。`SavedStudyContentScreen` 依 online 分文案；**offline 絕不顯示成 revoked**。offline 完全不碰 repo（不落地 church-private）。
- 測試：`test/saved_offline_revoked_test.dart`（3 案：online-未授權=無存取／offline=無法驗證／online-授權=可開）。flutter test 127／rules 91／analyze clean／兩 build 通過。
- （已於下一輪完成，見「ANNOTATION COEXISTENCE」。）

### ANNOTATION SAME-VERSE PUBLIC + CHURCH COEXISTENCE（最後 R1 blocker 完成，branch `claude/bible-app-setup-xi8bvd`）
**同一節可有零到多筆授權註解**（public＋各教會各自獨立、互不覆寫），Reader 雙區塊呈現。**Reader core 完全未動**——只擴充 annotation provider 輸出 shape、分組與 presentation。
- **Identity 解耦**：`annotations/{annotationId}`＝一筆受管理註解（有自己的 id）；`verse_key`="b_c_v"＝scripture lookup **欄位**（非 doc id）。legacy `verse_{b}_{c}_{v}` doc **id 不變**（annotation_id＝該 id），migration 補 `audience`＋`verse_key`（additive、idempotent、**不新建 doc、無重複、無 double-render**）。新註解 id＝`ann_{b}_{c}_{v}_{scope}_{unique}`（public/church、Church A/B 皆不 collision）。
- **Provider**：`chapterAnnotationProvider.verses` 由 `Map<int,VerseAnnotation>` → **`Map<int,List<VerseAnnotationView>>`**（`models.dart` 新 `VerseAnnotationView{verse,isChurch,annotationId,ann}`）。分組來源＝`cloudAnnotationsProvider`（＝authorized universe：`fetchAuthorizedAnnotations` public∪my-active-church，**未授權教會 doc 根本不在內**）。排序：**public 先、church 後**，同 audience 內 annotationId 升冪（deterministic，不靠 Firestore 回傳序）。`_verseLocOf` 以 `verse_key` 為主、legacy doc-id 為輔解析。`activeChurchNameProvider`＝教會標題（純 presentation，非授權依據）。
- **Reader 雙區塊**（`chapter_screen.dart` `_showVerseActions` 吃 `List<VerseAnnotationView>`）：字義/背景/應用/相關四個 Tab 各自**依註解分區塊**（`sectionHeader`＝`annotationSectionLabel(isChurch,churchName)`：public→「公開註釋」、church→「[教會名] · 教會專屬」）。CASE A 只 public、B public+church、C 只 church、D 多 public、E 多 church 皆支援。**未 active／pending／rejected／revoked／offline → cloud 只含 public → 只顯示公開**（不暴露其他教會存在）。快速動作/螢光筆/書籤/筆記/複製/投稿/社群註解**全未動**。
- **Admin**：`admin_annotation_screen.dart`（`AdminVerseAnnotationsScreen` 列同節多筆＋status/audience badge；`AdminAnnotationEditor` 欄位＋audience SegmentedButton＋active-church FilterChips＋workflow）。走既有 `ContentWorkflowService`（type=`annotations`）：Draft(預設 internal)→送審→發布→`createDraftFromPublished`（Published 唯讀、改內容/改 audience 皆走新草稿）。`services/annotation_admin_repository.dart`＝`AnnotationAdminRepository`（saveDraft 帶 verse_key、newAnnotationId、listForVerse union workspace∪published∪legacy、`_assertChurchPublishable` church 空/inactive 阻擋）。`AdminChapterScreen` 每節改開此新畫面（legacy `AdminVerseEditor` 保留未刪）。同節 public 與 church 各自獨立 doc、編輯互不覆寫。
- **Rules/indexes**：`annotations/{doc}` 已是 `audienceOK()||isAdmin()`（任意 doc-id → 多 doc 天生支援）；`annotations_workspace` admin-only。indexes 已有 annotations (status,audience)(+array)。**無新增 rules/indexes 需求**（沿用既有），未 deploy。
- **Migration**：`tools/migrate_audience.mjs` 擴充：annotation published→public、其餘→internal（idempotent skip），並補 `verse_key`（legacy verse doc id 解析；`verseKeyForAnnotationDoc`）。**絕不自動產生 church、doc id 不變、不建新 doc**。`tools/migrate_audience_test.mjs`（20 純函式案：mapping/idempotency/never-church/verse_key 解耦/deterministic）。**未 production apply。**
- **測試**：`test/annotation_coexistence_test.dart`（10：provider 分組次序 CASE A/B/C/D/E、fetchAuthorized 同節 public+chA/chB 過濾、Admin 同節雙 doc 不覆寫、church publishable 驗證、draft→送審→發布→授權讀）＋`test/annotation_presentation_test.dart`（6：label／dual-section 次序）＋rules coexistence 9 案（同節 public+chA+chB、by-id 不 bypass、no-membership public-only、church 空 deny）。**flutter test 143／rules 100／analyze clean／兩 build 通過／migration 純函式 20／dry-run fail-closed。**
- **Offline/cache**：`cloudAnnotationsProvider` **只快取 public**（church-private 不落地）；offline → 只回 public 快取。logout/account-switch 沿用既有 auth-scoped 失效（private 不跨 user）。

## Daily Verse Admin R1 ＋ Q&A AnswerSource Admin R1（branch `claude/bible-app-setup-xi8bvd`，baseline f2f0da2）

**Daily Verse Admin**（`screens/admin_daily_verse_screen.dart`，沿用 ContentWorkflowService type=`daily_verses`、contentId=日期）：List 加 Today/Future/Past ＋「有新版草稿」指示；Create=日期＋節位（VerseLocator authority）＋選填 title/content；Draft→送審（summary 確認）→Review（唯讀，發布前**最終確認**／退回修改）→Published（唯讀→建立替代草稿，日期 identity lock）→Archive；**版本紀錄**（唯讀，`adminListDailyVerses` 帶 `_versions`/`_published_*`）；**預覽學生首頁**（不寫、不改狀態、用草稿 snapshot＋Bible 經文）。學生 `_DailyVerseCard` 渲染選填 title/content（`publishedDailyVerseProvider` 擴充帶 title/content）。學生顯示＝`dailyVerseVisibleToday`（published 且 date==今天，未來不提前、過去不 auto-archive、無則 fail-closed、**不 fallback**）。

**Q&A AnswerSource Admin**（Church-sourced answer confidentiality）：核心 invariant＝**鎖 source link 不足以保護 church 內容；使用 church source 的 Answer 本身也要 audience-authorized**。
- **model**（`models/managed_content.dart`）：`AnswerSource` 加 `allowedChurchIds`（church source 授權快照，供交集）；`services/qa_service.dart` `Question` 加 `audience`/`allowedChurchIds`＋`studentReadable(activeChurchId)`（published 且 public∪church∩active；missing/internal→fail-closed）。
- **derive**（純函式，`DerivedAnswerAudience.derive`，B9/B10）：scripture/public→Public；任一 church source→Church，allowedChurchIds＝所有 church source 的**交集**；交集空／internal source→**不可發布**。`sourceProblem(...)`＝發布前單源重驗（非 Published／版本漂移／Internal → 阻止）。
- **service**：`publishAnswer(id,audience,allowedChurchIds)` 寫入推導後 audience（管理員不得放寬）；`setPublished(true)` 封鎖（必走 publishAnswer）；`publishedQuestions/retrieveApproved/ask` 加 `StudentAuth?` 過濾（防禦性同源，rules 為真正邊界）。
- **admin UI**（`qa_screen.dart`）：按鈕文案「儲存回答並公開」→**「儲存回答」**（saveAnswer≠publish）；picker 只列 Published、Internal **disabled**（B6）、church 顯示教會名（B5）；**發布範圍預覽**（依 sources 自動推導，read-only）；發布走 `_publishWithSourceValidation`＝逐源 LIVE 重驗（版本 exact／不 drift）＋推導 audience＋church 空交集擋＋**最終確認**（Public/指定教會文案）。學生 source tile：exact-version authorized 可點；stale「引用版本 vN·來源已有新版」不可點；archived「來源已封存」；church 未授權「目前無法存取」；internal fail-closed 不可點。
- **rules**（`firestore.rules`）：`questions` 讀改 `qaAudienceOK()`（published 且 public∪church∩active-membership；missing/internal→fail-closed）＋本人/admin。**無新 index 需求**。
- **schema 影響（additive）**：questions 加 `audience`/`allowed_church_ids`（由 publishAnswer 寫）；AnswerSource 加 `allowed_church_ids`。**⚠️ 既有 published Q&A 無 audience → 部署新 rules 後對學生 fail-closed 隱藏**，需另開 backfill stage（本輪未做、未 deploy）。
- **測試**：`test/qa_answersource_test.dart`（20：derive 矩陣／studentReadable／publishedQuestions 授權過濾／publishAnswer 寫入／sourceProblem cases 10-14／序列化）＋`test/daily_verse_admin_test.dart`（11：date gate／workflow／replacement 版本＋one-active-per-date／published 唯讀／archive fail-closed／title-content）＋rules Q&A audience 8 案。**flutter test 174／rules 108／analyze clean／兩 build 通過。** Q&A safety contract 未改（human-curated／no LLM／no Web／insufficient／pending 不入語料）。無 deploy／無 migration apply／無 production 觸碰。

## Admin R1 收尾（Daily Verse timezone/list ＋ Q&A Teacher Area capability，baseline 0eae880）

只補 partial/missing gap，不重寫既有（大部分 A/B 已於 4df42ce 完成、Teacher Area capability contract 已於 PR#6 完成，皆沿用）。
- **§A5 權威日期鍵＝Asia/Taipei**：新 `utils/date_key.dart`（`taipeiTodayYmd`/`taipeiYmd`，UTC+8 固定）。Student `_todayYmd`、Admin list `todayYmd`、新建預設日、Preview 一律共用，**不再用裝置時區**。`test/date_key_test.dart`（3）。
- **§A2/§A11 Daily Verse list**：加狀態 filter（全部/草稿·審核/已發布/已退回/已封存）、現行服務中 Published 版本＋publishedAt/publisher、「有新版草稿（服務中仍為現行 Published）」、**今日無服務中 Published 高可見度警示**。screen 改 ConsumerStatefulWidget（Riverpod 3 無 StateProvider，用 local state）。
- **§B7 Q&A Teacher Area capability**：`AnswerSource.requiredCapabilities`＋`Question.requiredCapabilities`；`DerivedAnswerAudience` 聯集 requiredCapabilities（teacher-area source＝`['teacher_area']`，以 live `teacher_book_id` 判定）；`studentReadable(activeChurchId,{activeChurchHasTeacherArea})` 加 capability gate；`publishAnswer` 寫 `required_capabilities`；`publishedQuestions/retrieveApproved/ask` 吃 `activeChurchHasTeacherArea`（provider 由 `teacherEntryVisibleProvider` 提供）。picker 標「老師專區 · Church · …」；audience 預覽標「該教會須具老師專區權限」。
- **rules**：`qaCapabilitiesOK()`（required_capabilities 含 teacher_area → 需 `activeChurchHasTeacherArea()` get capabilities doc；缺欄位 `in` guard 不加限制）併入 `qaAudienceOK()`。additive schema（questions 加 `required_capabilities`；AnswerSource 加 `required_capabilities`），無新 index。
- **測試**：qa_answersource_test 加 Teacher Area capability（8）；rules 加 teacher_area gate（4，用既有 churches/A cap=true、churches/B cap=false 種子）。**flutter test 190／rules 123／analyze clean／兩 build 通過。**
- **未做（partial/deferred，gap matrix 已列）**：Daily Verse structured Book→Chapter→Verse selector＋range（§A3；目前 ref-text＋VerseLocator，結構 locator 已存，input 仍文字、無範圍）；one-active-per-date 顯式 transaction（§A6；結構 doc-id=date 已保證單一 active，無 runTransaction 併發拒絕）。無 deploy／migration／backfill／production 觸碰。

## 開發守則（歷史教訓）

1. **深色模式**：顏色一律走 Theme / `AppTheme.highlightColor(c, isDark)`，不寫死
2. **GridView 不放進可捲動父層**（semantics 衝突會 crash）→ 用 `Wrap`（章節格就是這樣做的）
3. **InkWell 裡的 Positioned 按鈕**必須在 SizedBox 邊界內，否則點不到
4. **所有 async load 都要 try-catch，且 finally 裡收尾**（不然畫面一直轉圈）；DB 寫入後在 `finally` 裡 invalidate providers
5. 測試後門（跳過登入等）加的時候就記進下方待辦，上線前移除

## 網頁版與 Render 部署

- 平台雙軌：手機用原生 sqflite，網頁用 WASM+IndexedDB（`db_factory_native.dart` / `db_factory_web.dart` 條件式 import）
- 字型：打包 Noto Sans TC **子集**（`assets/fonts/NotoSansTC.ttf`，約 3,170 字，12MB→1.1MB）。**字集來源＝聖經全文 ∪ annotations.json ∪ `lib/**/*.dart` 裡所有 CJK 字**（用正則抓原始碼裡的中文，未來新增 UI 文案只要重跑腳本就涵蓋，不用手維護字表）。
- 重跑子集化步驟：下載完整版 NotoSansTC variable font → `fonttools varLib.instancer 字型 wght=400 -o 400.ttf` → 掃 cuv.json/annotations.json/lib 收字 → `fonttools subset 400.ttf --text-file=字集 --output-file=assets/fonts/NotoSansTC.ttf --layout-features='*'`。（**注意：assets 裡的字型已是子集，重跑前要重新下載完整版**）
- `web/index.html` 鎖定 **完整版 CanvasKit**（`canvasKitVariant: "full"`）：chromium 精簡版在部分環境整頁無字，勿改回
- build 一律 `flutter build web --release --no-web-resources-cdn`（不依賴 Google CDN）
- 部署：Render 靜態站，`render.yaml` + `render-build.sh`（Render 上會自己下載 Flutter、抓 sqlite3.wasm、build；本機環境抓不到 sqlite3.wasm 是網路政策，Render 上沒問題）
- **不要在 render.yaml 加 COOP/COEP headers**：same-origin 會擋 Firebase 登入 popup；sqflite WASM 不需要（走 IndexedDB）

## Mac 環境注意事項

1. Flutter SPM 已停用：`flutter config --no-enable-swift-package-manager`
2. pod install 必加語系前綴：`LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 pod install`
3. Firebase iOS SDK 第一次 pod install 需要 GitHub 連線（必要時開 Cloudflare WARP）
4. 模擬器：iPhone 17 Pro，ID `670AE065-01EA-4E24-B829-97FB79484E1A`；Google/Apple 登入要用真機測

## 驗證指令

```bash
flutter analyze
flutter test
```

## Firebase 接入步驟（要在 Mac 上做）

1. Firebase Console 建專案（console.firebase.google.com），開 Authentication（Google/Apple）與 Firestore
2. `dart pub global activate flutterfire_cli`，然後專案根目錄跑 `flutterfire configure`（產生 `firebase_options.dart`）
3. `flutter pub add firebase_core firebase_auth cloud_firestore`
4. pod install 記得語系前綴（見上）；第一次需要 GitHub 連線
5. 然後回來叫 Claude 寫 sync service：本地 SQLite 為主、Firestore 為備份，
   四張表（bookmarks/highlights/notes/reading_log）各要 upload/download，
   以 `updated_at`/`created_at` 做 last-write-wins

## 構想白板 backlog（Heptabase「聖經app架構」，2026-07-05 版）

已做 ✅ / 未做 ⬜（雲=需要後端/Firebase，容=需要人工內容）

**一、基本功能**：✅ 章節瀏覽、字級、夜間模式、複製整節、**兩種閱讀模式（逐節/整章連續）**　⬜ 顯示另一語言（需第二中文譯本 asset；新標點和合本有版權，不可下載）
**二、註解內容模組**：✅ 架構＋UI＋範例內容、每節公開註解審核（雲）　⬜ 補齊各章內容（容，編輯 annotations.json）
**三、搜尋與索引**：✅ 全文搜尋、模糊/子序列搜尋、節位快速鍵、搜尋歷史、筆記搜尋、人物/地點/事件搜尋
**四、主題式閱讀**：✅ 主題分類頁、**主題導讀欄位**、**讀經計畫（進度追蹤）**、人生情境入口、每日經文、**聽聖經（TTS）**　⬜ 主題導讀「文字」（容，使用者撰寫）、主題式選經計畫內容（容）
**五、個人信仰整理**：✅ 經文筆記、三欄模板、標籤、收藏、螢光多色**可命名**、筆記匯出（Markdown＋HTML 可存 PDF/用 Word 開）、讀經紀錄/進度、首頁筆記預覽、**主日證道筆記**、統計小卡、**我的信仰地圖**　⬜ 私密/公開（部分＝公開投稿已做，私密即本地筆記）
**六、疑問 Q&A**（雲，**全人工無 AI**）：✅ 提問、分類（神學/生活/爭議/其他）、問題搜尋、管理者親自回答、回答引用經文（可跳轉）＋標籤、精選置頂、回答編輯、回答更新紀錄、問題審核、問題收藏、追蹤（有新回答的未讀提示）　⬜ 真推播通知（需 FCM，目前是 App 內未讀提示）、登入實測
**七、交叉與知識架構**（框架已建，內容⛔使用者親寫）：✅ 平行經文對照、預表/應驗、聖經時間軸/事件線、人物生平＋重大事件、人物關係（可跳轉關係鏈）——格式＋UI＋空狀態就緒（`knowledge.json`）；相關經文推薦沿用既有 crossRefs　⬜ 內容填寫（容）、畫布式人物關係圖（目前是關係鏈導覽，非節點圖）
**八、帳號與技術**（雲）：✅ 自動儲存、雲端同步、**同步刪除（tombstone）**、**登入實測通過**（Google，桌機 Chrome＋手機，含雲端寫入 `users/{uid}` 與跨裝置/刪除同步）　⬜ Apple 登入實測、Mac Safari 同步相容（Firestore 長連線在 Mac Safari 會卡，暫以 Chrome 為準）
**九、120堂課程學習區**（容）：⬜ 白板上還是空的（無內容）
**資料整理卡**：✅ 語音朗讀（TTS）、離線優先　⬜ 向量化知識庫（AI 問答，需後端/API）、混合快取
**新想法**：⬜ 共讀小組（雲）、代禱連結（雲）

## 待辦

- [x] 登入實測與修復（已通）：修法＝render.yaml COOP 改 `same-origin-allow-popups`＋Firestore 強制 long-polling＋同步進度/逾時顯示。已知限制：Mac Safari 同步會卡（用 Chrome）、iOS Safari 需關「防止跨網站追蹤」。
- [ ] Mac Safari Firestore 同步相容（要不要專門修，待定；目前 Chrome/手機皆正常）
- [ ] **補齊註解內容**（目前只有創1 範例，格式已定，後台或編輯 annotations.json；⛔ 使用者親寫）
- [ ] 主題導讀文字、主題式讀經計畫選經（⛔ 使用者親寫；欄位/UI/排程框架已就緒）
- [ ] 交叉引用資料集（OpenBible cross-refs）→ 動前先確認內容邊界
- [ ] 疑問 Q&A **已做**（全人工）；剩真推播（FCM）與登入實測
- [ ] 共讀小組 / 代禱連結 / AI 問答（皆需後端＋登入實測）
- [ ] iOS 真機測試（icon、launch screen 還是預設的）

### 已完成（本輪）
信仰地圖、讀經計畫（進度追蹤 DB v5）、主題導讀欄位、聽聖經 TTS、同步刪除 tombstone（DB v6）、
筆記 HTML 匯出（可存 PDF/Word）、螢光筆可命名、**疑問 Q&A 全人工系統**（提問/分類/搜尋/
人工回答含引用經文＋標籤/精選/回答更新紀錄/審核/收藏/追蹤未讀提示）。
