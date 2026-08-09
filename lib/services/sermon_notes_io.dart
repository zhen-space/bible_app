import '../models/models.dart';

/// 主日／證道筆記的匯出／匯入格式（人可讀的 Markdown，可來回轉換）。
///
/// 一則筆記＝一個 `## 標題` 區塊，內含固定欄位小標 `#### 主題/日期/經文/位格/
/// 筆記/祂的話/實踐/感想`，每則以 `---` 分隔。欄位內容可跨多行。
/// 使用者可自己在檔案裡照這格式打好再匯入；匯出的檔案也能原樣匯回。
/// ⛔ 這裡只做「格式轉換」，不生成任何筆記內容。

/// 小標中文名 → SermonNote 欄位。
const _labelToField = {
  '主題': 'title',
  '日期': 'date',
  '經文': 'scripture',
  '位格': 'who',
  '筆記': 'content',
  '祂的話': 'word',
  '實踐': 'practice',
  '感想': 'reflection',
};

String _fmtDate(int millis) {
  final d = DateTime.fromMillisecondsSinceEpoch(millis);
  return '${d.year}/${d.month.toString().padLeft(2, '0')}/'
      '${d.day.toString().padLeft(2, '0')}';
}

/// 解析 `2026/08/09`、`2026-8-9` 等 → epoch millis；失敗回 null。
int? _parseDate(String s) {
  final m = RegExp(r'(\d{4})[/\-.](\d{1,2})[/\-.](\d{1,2})').firstMatch(s);
  if (m == null) return null;
  final y = int.tryParse(m.group(1)!);
  final mo = int.tryParse(m.group(2)!);
  final d = int.tryParse(m.group(3)!);
  if (y == null || mo == null || d == null) return null;
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  return DateTime(y, mo, d).millisecondsSinceEpoch;
}

/// 多則筆記 → 一份 Markdown 文字（匯出用）。
String sermonNotesToText(List<SermonNote> notes) {
  final b = StringBuffer('# 主日・證道筆記\n');
  for (final n in notes) {
    b
      ..writeln()
      ..writeln('## ${n.title.isEmpty ? '(未命名)' : n.title}')
      ..writeln()
      ..writeln('#### 主題')
      ..writeln(n.title)
      ..writeln()
      ..writeln('#### 日期')
      ..writeln(_fmtDate(n.date))
      ..writeln()
      ..writeln('#### 經文')
      ..writeln(n.scripture)
      ..writeln()
      ..writeln('#### 位格')
      ..writeln(n.trinityWho)
      ..writeln()
      ..writeln('#### 筆記')
      ..writeln(n.content)
      ..writeln()
      ..writeln('#### 祂的話')
      ..writeln(n.trinityWord)
      ..writeln()
      ..writeln('#### 實踐')
      ..writeln(n.practice)
      ..writeln()
      ..writeln('#### 感想')
      ..writeln(n.reflection)
      ..writeln()
      ..writeln('---');
  }
  return b.toString();
}

/// 一份文字 → 多則筆記（匯入用）。認得上面格式的 `#### 小標`，
/// 以 `---` 或下一個 `##`/`#` 標題分隔筆記；認不出格式就回空陣列。
/// 回傳的筆記 id/createdAt 皆為預設（存檔時 DB 會給新的 created_at）。
List<SermonNote> parseSermonNotes(String text) {
  final now = DateTime.now().millisecondsSinceEpoch;
  final notes = <SermonNote>[];
  Map<String, List<String>>? cur;
  String? curField;

  void flush() {
    final m = cur;
    if (m == null) return;
    cur = null;
    curField = null;
    String val(String k) => (m[k]?.join('\n') ?? '').trim();
    final hasAny = _labelToField.values.any((k) => val(k).isNotEmpty);
    if (!hasAny) return;
    notes.add(SermonNote(
      date: _parseDate(val('date')) ?? now,
      title: val('title'),
      scripture: val('scripture'),
      content: val('content'),
      trinityWho: val('who'), // 自填分類，不再限定固定選項
      trinityWord: val('word'),
      practice: val('practice'),
      reflection: val('reflection'),
      createdAt: 0,
      updatedAt: 0,
    ));
  }

  for (final raw in text.split('\n')) {
    final t = raw.trim();
    if (t == '---' || t == '***' || t.startsWith('## ') || t == '#' ||
        t.startsWith('# ')) {
      // 筆記分隔或裝飾標題：結束目前這則。
      flush();
      continue;
    }
    if (t.startsWith('#### ')) {
      final label = t.substring(5).trim();
      final field = _labelToField[label];
      if (field != null) {
        cur ??= {};
        curField = field;
        cur![field] = [];
        continue;
      }
    }
    if (curField != null) {
      cur![curField]!.add(raw);
    }
  }
  flush();
  return notes;
}
