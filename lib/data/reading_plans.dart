/// 讀經計畫（白板「四、主題式閱讀 → 讀經計畫」）。
///
/// 計畫的「進度」在本機 DB（plan_progress 表，可雲端同步）；
/// 這裡的排程是**純機械產生**——把經文按正典順序平均切成 N 天，
/// 不含任何撰寫內容（主題式的選經計畫屬使用者內容，之後由後台補）。
library;

import '../models/models.dart';

/// 一天要讀的一章。
class ChapterRef {
  final int bookId;
  final int chapter;

  const ChapterRef(this.bookId, this.chapter);
}

class ReadingPlan {
  final String id;
  final String name;
  final String subtitle;
  final String emoji;

  /// 目標天數（會把範圍內的章平均分成這麼多天）。
  final int days;

  /// 範圍：'all' 全本、'ot' 舊約、'nt' 新約。
  final String scope;

  const ReadingPlan({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.emoji,
    required this.days,
    this.scope = 'all',
  });

  /// 範圍內所有章的平坦清單（正典順序）。總項目數＝此清單長度。
  List<ChapterRef> flatChapters(List<Book> books) {
    final flat = <ChapterRef>[];
    for (final b in books) {
      if (scope == 'ot' && b.testament != 'ot') continue;
      if (scope == 'nt' && b.testament != 'nt') continue;
      for (var c = 1; c <= b.chapterCount; c++) {
        flat.add(ChapterRef(b.id, c));
      }
    }
    return flat;
  }

  /// 依實際卷章數，把範圍內的章平均切成 [days] 天。
  List<List<ChapterRef>> schedule(List<Book> books) {
    final flat = flatChapters(books);
    final out = <List<ChapterRef>>[];
    final n = flat.length;
    final base = n ~/ days;
    final extra = n % days; // 前面 extra 天各多一章，分得最平均
    var i = 0;
    for (var d = 0; d < days; d++) {
      final take = base + (d < extra ? 1 : 0);
      out.add(flat.sublist(i, i + take));
      i += take;
    }
    return out;
  }
}

/// 內建計畫（機械排程；主題式選經計畫日後由後台內容補上）。
const List<ReadingPlan> readingPlans = [
  ReadingPlan(
    id: 'whole-365',
    name: '一年通讀聖經',
    subtitle: '365 天讀完全本，每天約 3–4 章',
    emoji: '📖',
    days: 365,
  ),
  ReadingPlan(
    id: 'whole-90',
    name: '90 天速讀全本',
    subtitle: '每天約 13 章，三個月讀完',
    emoji: '⚡',
    days: 90,
  ),
  ReadingPlan(
    id: 'nt-90',
    name: '新約 90 天',
    subtitle: '只讀新約，每天約 3 章',
    emoji: '✝️',
    days: 90,
    scope: 'nt',
  ),
];
