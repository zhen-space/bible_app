import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/topics.dart';
import '../models/models.dart';
import '../services/annotation_repository.dart';
import '../services/bible_repository.dart';
import '../services/content_service.dart';
import '../services/database_service.dart';
import '../services/sync_service.dart';
import '../services/verse_locator.dart';

/// 管理者帳號（後台入口只對這個 Google 帳號顯示；
/// Firestore 規則端也用同一個 email 把關）。
const String kAdminEmail = 'zhen20091212@gmail.com';

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
  static const min = 16.0;
  static const max = 34.0;

  @override
  double build() {
    _load();
    return 21.0; // 預設放大，讀起來更舒服
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

/// 閱讀模式：逐節（一句一行）或段落（自然分段連續）。持久化。
enum ReadingMode { verse, paragraph }

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
        // 舊版存的 'flowing' 對應到現在的 paragraph
        if (v == 'flowing') {
          state = ReadingMode.paragraph;
        } else {
          state = ReadingMode.values.firstWhere((m) => m.name == v,
              orElse: () => ReadingMode.verse);
        }
      }
    } catch (_) {}
  }

  Future<void> toggle() async {
    state = state == ReadingMode.verse
        ? ReadingMode.paragraph
        : ReadingMode.verse;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, state.name);
  }
}

final readingModeProvider =
    NotifierProvider<ReadingModeNotifier, ReadingMode>(ReadingModeNotifier.new);

/// 中英對照開關（開啟時每節中文下方顯示英文 KJV）。持久化。
class BilingualNotifier extends Notifier<bool> {
  static const _key = 'bilingual';

  @override
  bool build() {
    _load();
    return false;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getBool(_key) ?? false;
    } catch (_) {}
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, state);
  }
}

final bilingualProvider =
    NotifierProvider<BilingualNotifier, bool>(BilingualNotifier.new);

/// 開啟中英對照時載入英文 KJV（4.5MB，只在需要時載一次）。
final englishReadyProvider = FutureProvider<bool>((ref) async {
  if (!ref.watch(bilingualProvider)) return false;
  await ref.watch(bibleRepositoryProvider).loadEnglish();
  return true;
});

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

final contentServiceProvider = Provider((ref) => ContentService());

/// 雲端內容層：annotations collection 全部 doc（Firebase 不可用或離線時為空，
/// 讀經端自動退回 asset 內容）。
final cloudAnnotationsProvider =
    FutureProvider<Map<String, Map<String, dynamic>>>((ref) async {
  if (!ref.watch(firebaseReadyProvider)) return const {};
  try {
    return await ref.watch(contentServiceProvider).fetchAll();
  } catch (_) {
    return const {};
  }
});

/// 整卷書的導讀＋統整（獨立標籤方格用）。雲端優先、asset 為底。
final bookAnnotationProvider =
    FutureProvider.family<BookAnnotation?, int>((ref, bookId) async {
  final cloud = await ref.watch(cloudAnnotationsProvider.future);
  final doc = cloud['book_$bookId'];
  if (doc != null) return BookAnnotation.fromJson(doc);
  return ref.watch(annotationRepositoryProvider).book(bookId);
});

/// 章導讀 + 該章的節註解（白板「二、註解內容模組」）。雲端優先、asset 為底。
final chapterAnnotationProvider = FutureProvider.family<
    ({ChapterAnnotation? chapter, Map<int, VerseAnnotation> verses}),
    ({int bookId, int chapter})>((ref, args) async {
  final repo = ref.watch(annotationRepositoryProvider);
  final cloud = await ref.watch(cloudAnnotationsProvider.future);

  final cloudChapter = cloud['chapter_${args.bookId}_${args.chapter}'];
  final chapter = cloudChapter != null
      ? ChapterAnnotation.fromJson(cloudChapter)
      : await repo.chapter(args.bookId, args.chapter);

  final verses = await repo.versesIn(args.bookId, args.chapter);
  final prefix = 'verse_${args.bookId}_${args.chapter}_';
  cloud.forEach((k, v) {
    if (k.startsWith(prefix)) {
      final verseNo = int.tryParse(k.substring(prefix.length));
      if (verseNo != null) verses[verseNo] = VerseAnnotation.fromJson(v);
    }
  });
  return (chapter: chapter, verses: verses);
});

/// 是否為管理者（後台入口顯示條件）。
final isAdminProvider = Provider<bool>((ref) {
  final user = ref.watch(authUserProvider).value;
  return user?.email == kAdminEmail;
});

/// 某章已通過的公開註解（verse → 多則）。Firebase 不可用或離線時為空。
final publicNotesProvider = FutureProvider.family<Map<int, List<PublicNote>>,
    ({int bookId, int chapter})>((ref, args) async {
  if (!ref.watch(firebaseReadyProvider)) return const {};
  try {
    return await ref
        .watch(contentServiceProvider)
        .approvedNotes(args.bookId, args.chapter);
  } catch (_) {
    return const {};
  }
});

/// 待審投稿佇列（管理者用）。
final pendingSubmissionsProvider =
    FutureProvider<List<PublicSubmission>>((ref) async {
  if (!ref.watch(firebaseReadyProvider)) return const [];
  return ref.watch(contentServiceProvider).pendingSubmissions();
});

final allBookmarksProvider = FutureProvider<List<Bookmark>>(
    (ref) => ref.watch(databaseServiceProvider).getAllBookmarks());
final allHighlightsProvider = FutureProvider<List<Highlight>>(
    (ref) => ref.watch(databaseServiceProvider).getAllHighlights());
final allNotesProvider = FutureProvider<List<Note>>(
    (ref) => ref.watch(databaseServiceProvider).getAllNotes());
final allSermonNotesProvider = FutureProvider<List<SermonNote>>(
    (ref) => ref.watch(databaseServiceProvider).getSermonNotes());
final statsProvider = FutureProvider<Map<String, int>>(
    (ref) => ref.watch(databaseServiceProvider).getStats());

/// 信仰地圖：每卷已讀章數 + 有標記節數。
final faithMapProvider = FutureProvider<
    ({Map<int, int> read, Map<int, int> marks})>((ref) async {
  final db = ref.watch(databaseServiceProvider);
  return (
    read: await db.getReadCountsByBook(),
    marks: await db.getMarkCountsByBook(),
  );
});

/// 各讀經計畫已完成天數（planId → 已完成天數），計畫列表用。
final planDoneCountsProvider = FutureProvider<Map<String, int>>(
    (ref) => ref.watch(databaseServiceProvider).getPlanDoneCounts());

/// 單一計畫已完成的天數集合。
final planProgressProvider =
    FutureProvider.family<Set<int>, String>((ref, planId) {
  return ref.watch(databaseServiceProvider).getPlanProgress(planId);
});

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
  String? build() {
    // 轉址登入回來（或任何時候從未登入變成已登入）→ 自動同步一次
    ref.listen(authUserProvider, (prev, next) {
      if (prev?.value == null && next.value != null) {
        syncNow();
      }
    });
    return null;
  }

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

  bool _signingIn = false; // 防止連點

  /// Google 登入。網頁用「轉址」流程：authDomain 已設為本站網域、
  /// /__/auth/* 由 Render 代理回 Firebase——全程同網域，iOS Safari 也可靠。
  /// 轉址回來後由 build() 裡的 auth 監聽自動觸發同步。
  Future<void> signIn() async {
    if (_signingIn) return;
    _signingIn = true;
    state = '前往 Google 登入…';
    try {
      if (kIsWeb) {
        await FirebaseAuth.instance
            .signInWithRedirect(GoogleAuthProvider());
        // 頁面即將整頁轉址離開；回來時已是登入狀態
      } else {
        await FirebaseAuth.instance
            .signInWithProvider(GoogleAuthProvider());
        state = '登入成功，同步中…';
        await syncNow();
      }
    } on FirebaseAuthException catch (e) {
      state = _friendlyError(e);
    } catch (e) {
      state = '登入失敗：$e';
    } finally {
      _signingIn = false;
    }
  }

  String? _friendlyError(FirebaseAuthException e) {
    switch (e.code) {
      case 'popup-closed-by-user':
        return '登入視窗被關閉，未完成登入。';
      case 'cancelled-popup-request':
        return '請再點一次「使用 Google 登入」。';
      case 'popup-blocked':
        return '瀏覽器擋掉了登入視窗。請到瀏覽器設定允許本網站的彈出式視窗，再試一次。';
      case 'operation-not-allowed':
        return 'Google 登入尚未在 Firebase 啟用：Authentication → Sign-in method → 啟用 Google。';
      case 'unauthorized-domain':
        return '本網站網址未加入授權：Firebase → Authentication → 設定 → 授權網域，新增本站網域。';
      case 'network-request-failed':
        return '網路連線失敗，請檢查網路後再試。';
      default:
        return '登入失敗：[${e.code}] ${e.message ?? ''}';
    }
  }

  Future<void> signOut() async {
    await FirebaseAuth.instance.signOut();
    state = null;
  }
}

final syncStatusProvider =
    NotifierProvider<SyncStatusNotifier, String?>(SyncStatusNotifier.new);
