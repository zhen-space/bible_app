import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/topics.dart';
import '../models/models.dart';
import '../services/annotation_repository.dart';
import '../services/bible_repository.dart';
import '../services/database_service.dart';
import '../services/sync_service.dart';
import '../services/verse_locator.dart';

final bibleRepositoryProvider = Provider((ref) => BibleRepository());
final databaseServiceProvider = Provider((ref) => DatabaseService());
final annotationRepositoryProvider = Provider((ref) => AnnotationRepository());

/// 全部書卷（App 啟動時載入一次）。
final booksProvider = FutureProvider<List<Book>>((ref) {
  return ref.watch(bibleRepositoryProvider).loadBooks();
});

/// 主題模式，持久化到 SharedPreferences。
class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const _key = 'theme_mode';

  @override
  ThemeMode build() {
    _load();
    return ThemeMode.system;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_key);
      if (v != null) {
        state = ThemeMode.values.firstWhere(
          (m) => m.name == v,
          orElse: () => ThemeMode.system,
        );
      }
    } catch (_) {
      // 讀取失敗就維持 system，不擋啟動。
    }
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

/// 內文字級，持久化。
class FontSizeNotifier extends Notifier<double> {
  static const _key = 'font_size';
  static const min = 14.0;
  static const max = 28.0;

  @override
  double build() {
    _load();
    return 18.0;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getDouble(_key);
      if (v != null) state = v.clamp(min, max);
    } catch (_) {}
  }

  Future<void> set(double size) async {
    state = size.clamp(min, max);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_key, state);
  }
}

final fontSizeProvider =
    NotifierProvider<FontSizeNotifier, double>(FontSizeNotifier.new);

/// 閱讀模式：逐節（一句一行）或整章（連續段落）。持久化。
enum ReadingMode { verse, flowing }

class ReadingModeNotifier extends Notifier<ReadingMode> {
  static const _key = 'reading_mode';

  @override
  ReadingMode build() {
    _load();
    return ReadingMode.verse;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_key);
      if (v != null) {
        state = ReadingMode.values.firstWhere((m) => m.name == v,
            orElse: () => ReadingMode.verse);
      }
    } catch (_) {}
  }

  Future<void> toggle() async {
    state = state == ReadingMode.verse
        ? ReadingMode.flowing
        : ReadingMode.verse;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, state.name);
  }
}

final readingModeProvider =
    NotifierProvider<ReadingModeNotifier, ReadingMode>(ReadingModeNotifier.new);

/// 上次閱讀位置（書卷+章），持久化。
class LastReadNotifier extends Notifier<({int bookId, int chapter})?> {
  static const _key = 'last_read';

  @override
  ({int bookId, int chapter})? build() {
    _load();
    return null;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_key);
      if (v != null) {
        final parts = v.split(':');
        state = (bookId: int.parse(parts[0]), chapter: int.parse(parts[1]));
      }
    } catch (_) {}
  }

  Future<void> set(int bookId, int chapter) async {
    state = (bookId: bookId, chapter: chapter);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, '$bookId:$chapter');
  }
}

final lastReadProvider =
    NotifierProvider<LastReadNotifier, ({int bookId, int chapter})?>(
        LastReadNotifier.new);

/// 某章的使用者標記（書籤/螢光筆/筆記），改動後 invalidate 重抓。
final chapterMarksProvider = FutureProvider.family<ChapterMarks,
    ({int bookId, int chapter})>((ref, args) async {
  final db = ref.watch(databaseServiceProvider);
  final bookmarks = await db.getBookmarkedVerses(args.bookId, args.chapter);
  final highlights = await db.getChapterHighlights(args.bookId, args.chapter);
  final notes = await db.getChapterNotes(args.bookId, args.chapter);
  return ChapterMarks(
      bookmarks: bookmarks, highlights: highlights, notes: notes);
});

class ChapterMarks {
  final Set<int> bookmarks;
  final Map<int, HighlightColor> highlights;
  final Map<int, Note> notes;

  const ChapterMarks({
    required this.bookmarks,
    required this.highlights,
    required this.notes,
  });
}

/// 搜尋歷史（最多 20 筆，持久化）。
class SearchHistoryNotifier extends Notifier<List<String>> {
  static const _key = 'search_history';

  @override
  List<String> build() {
    _load();
    return const [];
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getStringList(_key) ?? const [];
    } catch (_) {}
  }

  Future<void> add(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    state = [q, ...state.where((e) => e != q)].take(20).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, state);
  }

  Future<void> clear() async {
    state = const [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

final searchHistoryProvider =
    NotifierProvider<SearchHistoryNotifier, List<String>>(
        SearchHistoryNotifier.new);

/// 已讀章數（全聖經 1,189 章）。
final readChapterCountProvider = FutureProvider<int>(
    (ref) => ref.watch(databaseServiceProvider).getReadChapterCount());

/// 每日經文：依日期從主題經文池中固定挑一節（同一天大家看到同一節）。
final dailyVerseProvider = FutureProvider<VerseRef>((ref) async {
  final books = await ref.watch(booksProvider.future);
  final pool = dailyVersePool();
  final day = DateTime.now().difference(DateTime(2024)).inDays;
  final loc = VerseLocator.parse(pool[day % pool.length], books)!;
  final text =
      books[loc.bookId - 1].chapters[loc.chapter - 1][loc.verse! - 1];
  return VerseRef(
      bookId: loc.bookId, chapter: loc.chapter, verse: loc.verse!, text: text);
});

/// 整卷書的導讀＋統整（獨立標籤方格用）。
final bookAnnotationProvider =
    FutureProvider.family<BookAnnotation?, int>((ref, bookId) {
  return ref.watch(annotationRepositoryProvider).book(bookId);
});

/// 章導讀 + 該章的節註解（白板「二、註解內容模組」）。
final chapterAnnotationProvider = FutureProvider.family<
    ({ChapterAnnotation? chapter, Map<int, VerseAnnotation> verses}),
    ({int bookId, int chapter})>((ref, args) async {
  final repo = ref.watch(annotationRepositoryProvider);
  final chapter = await repo.chapter(args.bookId, args.chapter);
  final verses = await repo.versesIn(args.bookId, args.chapter);
  return (chapter: chapter, verses: verses);
});

final allBookmarksProvider = FutureProvider<List<Bookmark>>(
    (ref) => ref.watch(databaseServiceProvider).getAllBookmarks());
final allHighlightsProvider = FutureProvider<List<Highlight>>(
    (ref) => ref.watch(databaseServiceProvider).getAllHighlights());
final allNotesProvider = FutureProvider<List<Note>>(
    (ref) => ref.watch(databaseServiceProvider).getAllNotes());

// ---- 帳號與雲端同步（Firebase；未初始化時功能自動隱藏）----

/// Firebase 是否可用（main 裡 init 成功才會有 app）。
final firebaseReadyProvider = Provider<bool>((ref) => Firebase.apps.isNotEmpty);

/// 目前登入的使用者（null = 未登入或 Firebase 不可用）。
final authUserProvider = StreamProvider<User?>((ref) {
  if (Firebase.apps.isEmpty) return Stream.value(null);
  return FirebaseAuth.instance.authStateChanges();
});

final syncServiceProvider =
    Provider((ref) => SyncService(ref.watch(databaseServiceProvider)));

/// 同步狀態機：idle / syncing / 完成或錯誤訊息。
class SyncStatusNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  /// 執行一次完整同步；結束後刷新所有標記 providers。
  Future<void> syncNow() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    state = '同步中…';
    try {
      state = await ref.read(syncServiceProvider).syncAll(user.uid);
    } catch (e) {
      state = '同步失敗：$e';
    } finally {
      ref.invalidate(allBookmarksProvider);
      ref.invalidate(allHighlightsProvider);
      ref.invalidate(allNotesProvider);
      ref.invalidate(readChapterCountProvider);
      ref.invalidate(chapterMarksProvider);
    }
  }

  /// Google 登入（web 用 popup），成功後自動同步一次。
  Future<void> signIn() async {
    state = null;
    try {
      await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
      await syncNow();
    } catch (e) {
      state = '登入失敗：$e';
    }
  }

  Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
    state = null;
  }
}

final syncStatusProvider =
    NotifierProvider<SyncStatusNotifier, String?>(SyncStatusNotifier.new);
