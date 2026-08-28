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

`database_service.dart`，目前 **v13**（v2 reading_log；v3 notes.tags；v4 sermon_notes；v5 plan_progress；v6 tombstones；v7 prayers；v8 todos；**v9 chapter_completions**；**v10 plan_item_progress**；**v11 later**；**v12 notes.title/refs/deleted_at**；**v13 prayers v2 欄位**）。升版時：
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
