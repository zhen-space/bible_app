/// 非網頁平台：沒有瀏覽器下載能力（手機版用 Markdown 複製到剪貼簿即可）。
/// 回傳 false 表示此平台不支援檔案下載。
bool downloadTextFile(String filename, String mimeType, String content) =>
    false;

/// 非網頁平台：不支援「選檔案」；回 null，呼叫端改用貼上文字匯入。
Future<String?> pickTextFile() async => null;

/// 非網頁平台沒有檔案選取能力。
bool get canPickFile => false;
