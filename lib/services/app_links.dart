import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../screens/chapter_screen.dart';
import '../screens/knowledge_screen.dart';
import 'verse_locator.dart';

/// 原子化經文關聯（Deep Linking）：全 App 統一的「一鍵跨模組跳轉」入口。
///
/// 原子 ID 有兩種：
/// - **節位字串**（約3:16、太8:23-27）——聖經內容的唯一定位，
///   所有模組（註解 crossRefs、Q&A 引用、知識庫、主題）都用同一格式，
///   由 VerseLocator 解析後跳讀經頁（帶範圍取起點）。
/// - **人物 id**（knowledge.people 的 id，如 abraham）——跳人物詳情頁；
///   人物間的 relations 也用同一 id 串起來。
///
/// 各畫面一律呼叫這裡，不要自己 copy 跳轉邏輯（之前散在 3 處，已收攏）。
class AppLinks {
  /// 依節位字串跳讀經頁。解析失敗就安靜不動（不炸畫面）。
  static void openVerseRef(
      BuildContext context, WidgetRef ref, String refStr) {
    final books = ref.read(booksProvider).value;
    if (books == null) return;
    final loc = VerseLocator.parse(refStr, books);
    if (loc == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ChapterScreen(bookId: loc.bookId, chapter: loc.chapter),
      ),
    );
  }

  /// 依人物 id 跳人物詳情頁。
  static void openPerson(BuildContext context, String personId) {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => PersonDetailScreen(personId: personId)),
    );
  }
}
