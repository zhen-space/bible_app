import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../screens/chapter_screen.dart';
import '../screens/knowledge_screen.dart';
import 'verse_locator.dart';

/// 原子化經文關聯（Deep Linking）：全 App 統一的「一鍵跨模組跳轉」入口。
class AppLinks {
  /// 依節位字串跳讀經頁。連續範圍（例：約翰一書 4:7–8、約1:1-2:3）定位到範圍起點。
  /// 所有內容型引用都是臨時瀏覽，不更新一般 Reading Position。
  /// 回傳是否真的開啟（經文尚未載入或節位無法解析 → false，讓呼叫端告知使用者）。
  static bool openVerseRef(
      BuildContext context, WidgetRef ref, String refStr) {
    final books = ref.read(booksProvider).value;
    if (books == null) return false;
    final range = RegExp(r'^(.*?)(?:\s*[-–—]\s*\d{1,3}(?:\s*[:：]\s*\d{1,3})?)$')
        .firstMatch(refStr.trim());
    final parseTarget = range?.group(1)?.trim() ?? refStr.trim();
    final loc = VerseLocator.parse(parseTarget, books);
    if (loc == null) return false;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChapterScreen(
          bookId: loc.bookId,
          chapter: loc.chapter,
          focusVerse: loc.verse,
          updateReadingPosition: false,
        ),
      ),
    );
    return true;
  }

  static void openPerson(BuildContext context, String personId) {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => PersonDetailScreen(personId: personId)),
    );
  }
}
