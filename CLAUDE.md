# 聖經 App — 傳承文件

每次新 session 先讀這份文件。每次大改動後更新它。

## ⛔ 內容守則（使用者明令，不可違反）

**註釋、導讀等所有註解「內容」由使用者本人親自撰寫。Claude 一律不准新增、修改、生成或代填 `assets/annotations/annotations.json` 裡的文字內容。**
- 可以做：改「程式/UI/資料格式/顯示方式」、修 bug、加欄位。
- 不可以做：寫任何導讀、注釋、關鍵字、生活應用、重點等文字。
- 目前檔案裡只留創1（早期 Claude 產的範例，詩23/約3 已依使用者要求刪除），保留當**格式範本**即可；使用者要換成自己寫的內容。若使用者要求清空範例，才可刪。

## 專案概況

Flutter 聖經 App，**和合本神版**（繁體）離線讀經。功能：引導式首頁、讀經（**兩種閱讀模式**：逐節分行／整章連續）、**中英對照**（KJV，每節中文下接英文）、**聽聖經**（TTS 逐節朗讀，朗讀中的節即時高亮）、卷導讀（獨立方格）＋卷統整（整卷最後一章末）、每節註解（注釋/關鍵字/生活應用/交叉引用可跳轉）、讀經頁內建搜尋、全文搜尋（含模糊/子序列）、節位快速跳轉（約3:16）、搜尋歷史、主題閱讀（含**主題導讀**欄位）、**讀經計畫**（一年通讀/90天速讀/新約，逐日勾選進度）、人生情境入口、每日經文、讀經進度、**我的信仰地圖**（66 卷依已讀比例上色）、首頁個人筆記、書籤、螢光筆（5 色，**可命名**）、經節筆記（含觀察/相信/行動三欄模板、標籤）、主日證道筆記、統計小卡、筆記匯出（Markdown 複製／HTML 下載可存 PDF/用 Word 開）、深淺色主題、字級調整、記住閱讀位置。

- 配色（使用者要 Apple 風、不要像 Google）：淺色＝天空藍底（`_skyBg`）＋白圓角卡片＋**金圖標**＋黑字；深色＝深藍底＋白字＋金圖標。圖標色靠 `iconTheme`/`appBarTheme.actionsIconTheme`/`listTileTheme` 統一設金。iOS 感：大標題（左對齊粗體）、Card 圓角 18、elevation 0。見 `theme/app_theme.dart`。
- 登入：Google（已通）＋ Apple（`OAuthProvider('apple.com')` popup；需 Firebase 啟用 Apple provider、Apple Developer 建 Service ID 才會動）。
- **章層級導讀/重點已移除**（使用者要求）：讀經頁不顯示章導讀卡；導讀＝卷層級（books 頁「導讀」方格），統整＝卷層級（整卷最後一章末的「本卷統整」卡 + 「統整」方格）。
- 英文 KJV：`assets/bible/kjv.json`（4.5MB，公有領域），只在需要時（進讀經頁或開對照）載入；節數與和合本差 4 節，對不到的節不顯示英文。

- 聽聖經：`flutter_tts`（網頁走瀏覽器 SpeechSynthesis、手機走系統 TTS），`services/tts_service.dart` 逐節朗讀、追蹤目前節號供高亮；換章/離開頁自動停。
- 狀態管理：Riverpod（`flutter_riverpod`，Notifier/FutureProvider）
- 使用者資料：sqflite（存書籤/螢光筆/筆記/讀經紀錄/證道筆記/讀經計畫進度/刪除墓碑；**經文不進 DB**）
- 經文來源：`assets/bible/cuv.json`（約 3.3MB，66 卷 31,104 節），啟動時載入記憶體，搜尋直接掃記憶體
- 設定持久化：shared_preferences（主題、字級、閱讀位置）
- Firebase：**已接（Web 先行）**。專案 `bible-app-c0eac`；`lib/firebase_options.dart` 只有 web 設定（iOS/Android 之後在 Mac 跑 `flutterfire configure` 覆蓋該檔）。Google 登入（popup）＋ Firestore 雲端備份：`services/sync_service.dart` 多表雙向 LWW 合併（bookmarks/highlights/notes/reading_log/sermon_notes/plan_progress→`users/{uid}/...`）。**已支援同步刪除（tombstone）**：`tombstones` 表記錄刪除，不變量＝同一筆資料「活資料」與「墓碑」互斥（刪除寫墓碑、新增/更新清墓碑）；sync 先合併墓碑→下載擋掉被刪→套用墓碑刪本地→上傳墓碑並刪雲端 doc。main() 裡 init 失敗不擋 App；未登入一切照常。**新資料表記得加進 sync service，刪除要記墓碑**。

## 目錄結構

```
lib/
  main.dart                 App 入口，ProviderScope + MaterialApp
  models/models.dart        Book/VerseRef/Bookmark/Highlight/Note
  data/topics.dart          主題/情境精選經文（節位字串，有測試守著有效性）
  services/
    database_service.dart   SQLite（含升版框架，見下；目前 v6）
    bible_repository.dart   經文載入與搜尋（含模糊/子序列）
    verse_locator.dart      節位解析（「約3:16」→ bookId/章/節）
    annotation_repository.dart  註解內容載入（章導讀/節註解，可插拔）
    tts_service.dart        聽聖經（flutter_tts 逐節朗讀）
    download_web.dart / download_stub.dart  瀏覽器檔案下載（條件式 import）
  data/topics.dart          主題＋主題導讀（Topic.intro）
  data/reading_plans.dart   讀經計畫（機械排程，非撰寫內容）
  providers/providers.dart  所有 Riverpod providers
  theme/app_theme.dart      深淺色主題 + 螢光筆顏色
  screens/                  home / chapter / search / bookmarks / settings / topics /
                            book_overview / faith_map（信仰地圖）/ reading_plans（讀經計畫）/
                            sermon_notes（證道筆記）
assets/bible/cuv.json       和合本經文（見「經文資料」）
assets/annotations/annotations.json  註解內容（見「註解內容模組」）
```

## 註解內容模組（白板二）

- 資料在 `assets/annotations/annotations.json`，**內容可插拔、可缺**（缺就不顯示，不擋讀經）。
- key 格式：
  - `books['書卷id']`：**整卷導讀＋統整**（獨立標籤方格，見下），格式 `{ intro:{summary,purpose,author,background}, outline:[...], summary:'統整文字' }`
  - `書卷id:章`：章導讀（大意/目的/作者/背景/分段/重點）
  - `書卷id:章:節`：節註解（注釋/關鍵字/生活應用/交叉引用）
  - 書卷 id：創=1、詩=19、太=40、約=43。
- **導讀／統整標籤方格**：書卷章節格最前面固定一個「導讀」方格、最後面一個「統整」方格（`_OverviewBox`），開 `BookOverviewScreen`。方格永遠在；沒內容時顯示待填空白頁（不代寫內容）。
- 交叉引用（crossRefs）是節位字串，讀經頁點了會跳轉；可帶範圍（約1:1-3），跳轉時取破折號前。
- 目前只留 1 章示範內容（創1，使用者要求刪掉詩23/約3）。創1 可在後台編輯。**補內容 = 後台撰寫或編輯這個 JSON**，不用改程式。
- 章導讀「分段」欄（outline，如「1-8 各支派在營地的位置」）會解析成經文中的**段落標題**（`headingsFromOutline`）。
- 有測試守著：所有 key 在範圍內、所有交叉引用能解析。
- **管理後台（App 內）**：管理者（`kAdminEmail`＝使用者本人）登入後，設定頁出現「內容管理」。可在 App 內撰寫卷導讀/統整、章導讀/重點、節註解，存 Firestore `annotations` collection（doc id：`book_{id}` / `chapter_{id}_{章}` / `verse_{id}_{章}_{節}`，資料形狀同 asset JSON）。讀經端 `cloudAnnotationsProvider` 啟動抓一次，**雲端優先、asset 為底**合併。⛔ 內容仍由使用者親寫，Claude 只維護編輯器。
- **公開註解投稿＋審核**（白板「每句可個人註解但公開須經審核」）：登入者可在讀經頁對經節「投稿公開註解」→ Firestore `submissions`（status pending）。管理者在後台「公開註解審核」佇列 approve/reject；通過會複製到 `public_notes`（所有人可讀），讀經頁經節選單顯示「社群註解」。用 `loc='書卷id_章'` 單欄位查詢，免複合索引。⛔ 這是使用者投稿內容，非 Claude 代寫。

## 經文資料

- 來源：scrollmapper/bible_databases 的 `ChiUn.json`（和合本繁體，公有領域）
- 轉檔：清掉斷詞用的 ASCII 空格、保留「　神」前的全形空格（敬虔空格）、套 66 卷中文書名
- 格式：`{translation, translationId, books: [{id, name, abbr, testament, chapters: [[經文…]]}]}`
- `chapters[章-1][節-1]` 取經文，book id 1–66

## DB 升版規則（兩邊都要寫！）

`database_service.dart`，目前 v6（v2 加 reading_log；v3 加 notes.tags；v4 加 sermon_notes 證道筆記表；v5 加 plan_progress 讀經計畫進度；v6 加 tombstones 刪除墓碑）。升版時：
1. `_dbVersion` +1
2. `_onUpgrade` 加 `if (oldV < n)` 區塊
3. `_createAllTables` 同步加建表語句（全新安裝走這裡）

另外：`HighlightColor` enum 以 index 存 DB，**順序不能改**，只能往後加（有測試守著）。

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
**六、疑問 Q&A**（雲）：⬜ 全部——提問/分類/審核/通知，需要後端與管理者、登入實測
**七、交叉與知識架構**（容/資料）：⬜ 相關經文推薦、平行對照、時間軸、人物關係圖——需要 cross-reference 資料集（OpenBible.info cross-refs，公有領域）。**注意：crossRefs 目前混在節註解內容區，屬使用者內容邊界，動之前先問使用者**
**八、帳號與技術**（雲）：✅ 自動儲存、雲端同步、**同步刪除（tombstone）**　⬜ 登入實測（onrender.com 本環境連不到，需使用者週四手機/桌機測）、Apple 登入實測
**九、120堂課程學習區**（容）：⬜ 白板上還是空的（無內容）
**資料整理卡**：✅ 語音朗讀（TTS）、離線優先　⬜ 向量化知識庫（AI 問答，需後端/API）、混合快取
**新想法**：⬜ 共讀小組（雲）、代禱連結（雲）

## 待辦

- [ ] 登入實測與修復（環境連不到 onrender.com，Claude 無法盲測；已加 GIS client_id meta）
- [ ] **補齊註解內容**（目前只有創1 範例，格式已定，後台或編輯 annotations.json；⛔ 使用者親寫）
- [ ] 主題導讀文字、主題式讀經計畫選經（⛔ 使用者親寫；欄位/UI/排程框架已就緒）
- [ ] 交叉引用資料集（OpenBible cross-refs）→ 動前先確認內容邊界
- [ ] 疑問 Q&A / 共讀小組 / 代禱連結 / AI 問答（皆需後端＋登入實測）
- [ ] iOS 真機測試（icon、launch screen 還是預設的）

### 已完成（本輪）
信仰地圖、讀經計畫（進度追蹤 DB v5）、主題導讀欄位、聽聖經 TTS、同步刪除 tombstone（DB v6）、
筆記 HTML 匯出（可存 PDF/Word）、螢光筆可命名。
