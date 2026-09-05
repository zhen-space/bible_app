/// 每日經文的**權威日期鍵**（Church/Teacher R1 §A5）。
///
/// R1 固定使用 **Asia/Taipei（UTC+8，台灣無日光節約）**，**不使用裝置本地時區**。
/// Student Home、Admin、Preview 一律共用這裡的 helper，確保「今日內容」一致：
/// 使用者不論身在哪個時區，看到的「今天」都以台北日界為準。
library;

/// 台北時區固定偏移（UTC+8）。
const Duration kTaipeiOffset = Duration(hours: 8);

/// 把任一時間點格式成台北日期鍵 `YYYY-MM-DD`。
String taipeiYmd(DateTime instant) {
  final t = instant.toUtc().add(kTaipeiOffset);
  return '${t.year.toString().padLeft(4, '0')}-'
      '${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';
}

/// 現在（台北）的日期鍵。**Student/Admin/Preview 共用。**
String taipeiTodayYmd() => taipeiYmd(DateTime.now());
