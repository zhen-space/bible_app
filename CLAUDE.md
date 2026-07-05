# 聖經 App — 傳承文件

每次新 session 先讀這份文件。每次大改動後更新它。

## 專案概況

Flutter 聖經 App，和合本（繁體）離線讀經。功能：讀經、全文搜尋、書籤、螢光筆（5 色）、經節筆記、深淺色主題、字級調整、記住閱讀位置。

- 狀態管理：Riverpod（`flutter_riverpod`，Notifier/FutureProvider）
- 使用者資料：sqflite（只存書籤/螢光筆/筆記；**經文不進 DB**）
- 經文來源：`assets/bible/cuv.json`（約 3.3MB，66 卷 31,104 節），啟動時載入記憶體，搜尋直接掃記憶體
- 設定持久化：shared_preferences（主題、字級、閱讀位置）
- Firebase：**尚未加入**。規劃為「本地 SQLite 為主、Firestore 為備份」，需在 Mac 上跑 `flutterfire configure` 後加 firebase_core/firebase_auth/cloud_firestore，並建 sync service（每個資料表都要有 upload/download）

## 目錄結構

```
lib/
  main.dart                 App 入口，ProviderScope + MaterialApp
  models/models.dart        Book/VerseRef/Bookmark/Highlight/Note
  services/
    database_service.dart   SQLite（含升版框架，見下）
    bible_repository.dart   經文載入與搜尋
  providers/providers.dart  所有 Riverpod providers
  theme/app_theme.dart      深淺色主題 + 螢光筆顏色
  screens/                  home / chapter / search / bookmarks / settings
assets/bible/cuv.json       和合本經文（見「經文資料」）
```

## 經文資料

- 來源：scrollmapper/bible_databases 的 `ChiUn.json`（和合本繁體，公有領域）
- 轉檔：清掉斷詞用的 ASCII 空格、保留「　神」前的全形空格（敬虔空格）、套 66 卷中文書名
- 格式：`{translation, translationId, books: [{id, name, abbr, testament, chapters: [[經文…]]}]}`
- `chapters[章-1][節-1]` 取經文，book id 1–66

## DB 升版規則（兩邊都要寫！）

`database_service.dart`，目前 v1。升版時：
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

## 待辦

- [ ] Firebase 雲端同步（Mac 上 flutterfire configure；auth + Firestore 備份；sync service 含每表 upload/download）
- [ ] 讀經計畫 / 每日經文
- [ ] iOS 真機測試（icon、launch screen 還是預設的）
- [ ] Heptabase 構想白板的內容待補進來（連結需要登入，session 內打不開）
