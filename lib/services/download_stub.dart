/// 非網頁平台：沒有瀏覽器下載能力（手機版用 Markdown 複製到剪貼簿即可）。
/// 回傳 false 表示此平台不支援檔案下載。
bool downloadTextFile(String filename, String mimeType, String content) =>
    false;
