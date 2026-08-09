import 'dart:async';
import 'dart:convert';

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
import '../models/knowledge.dart';
import '../services/database_service.dart';
import '../services/knowledge_repository.dart';
import '../services/qa_service.dart';
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

/// 螢光筆命名（白板「高亮多色可命名」）：每個顏色可設一個意義標籤
/// （例：黃＝應許、綠＝命令）。存 SharedPreferences（顏色 index → 名稱）。
class HighlightLabelsNotifier extends Notifier<Map<HighlightColor, String>> {
  static const _key = 'highlight_labels';

  @override
  Map<HighlightColor, String> build() {
    _load();
    return const {};
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_key);
      if (list == null) return;
      final map = <HighlightColor, String>{};
      for (final entry in list) {
        final i = entry.indexOf('=');
        if (i <= 0) continue;
        final idx = int.tryParse(entry.substring(0, i));
        if (idx == null || idx < 0 || idx >= HighlightColor.values.length) {
          continue;
        }
        map[HighlightColor.values[idx]] = entry.substring(i + 1);
      }
      state = map;
    } catch (_) {}
  }

  Future<void> setLabel(HighlightColor color, String label) async {
    final next = Map<HighlightColor, String>.from(state);
    final trimmed = label.trim();
    if (trimmed.isEmpty) {
      next.remove(color);
    } else {
      next[color] = trimmed;
    }
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _key, [for (final e in next.entries) '${e.key.index}=${e.value}']);
  }
}

final highlightLabelsProvider =
    NotifierProvider<HighlightLabelsNotifier, Map<HighlightColor, String>>(
        HighlightLabelsNotifier.new);

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

/// 上次閱讀位置（書卷+章+**捲動位移**），持久化。
/// offset＝離開時的捲動像素位置，用來還原「讀到的畫面」而不只是章頂。
/// 用 offset（而非節號）是因為它對逐節／段落兩種模式都適用、且渲染穩定。
class LastReadNotifier
    extends Notifier<({int bookId, int chapter, double offset})?> {
  static const _key = 'last_read';

  @override
  ({int bookId, int chapter, double offset})? build() {
    _load();
    return null;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_key);
      if (v != null) {
        final parts = v.split(':');
        state = (
          bookId: int.parse(parts[0]),
          chapter: int.parse(parts[1]),
          // 舊格式（book:chapter）沒有 offset，預設 0（章頂）
          offset: parts.length > 2 ? (double.tryParse(parts[2]) ?? 0) : 0,
        );
      }
    } catch (_) {}
  }

  /// 換章時呼叫（offset 預設 0＝章頂）。
  Future<void> set(int bookId, int chapter, [double offset = 0]) async {
    state = (bookId: bookId, chapter: chapter, offset: offset);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, '$bookId:$chapter:${offset.toStringAsFixed(1)}');
  }

  /// 捲動時更新位移（章沒變才更新，避免蓋掉剛換的章）。
  Future<void> setOffset(int bookId, int chapter, double offset) async {
    final s = state;
    if (s == null || s.bookId != bookId || s.chapter != chapter) return;
    state = (bookId: bookId, chapter: chapter, offset: offset);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, '$bookId:$chapter:${offset.toStringAsFixed(1)}');
  }
}

final lastReadProvider = NotifierProvider<LastReadNotifier,
    ({int bookId, int chapter, double offset})?>(LastReadNotifier.new);

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

/// 混合式快取：雲端內容抓到就存 SharedPreferences；離線或抓取失敗時
/// 用上次快取（經文永遠在本地 asset，這裡只快取「雲端撰寫層」）。
Future<Map<String, dynamic>?> _readCache(String key) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

Future<void> _writeCache(String key, Map<String, dynamic> data) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(data));
  } catch (_) {} // 快取失敗不影響功能
}

/// 雲端內容層：annotations collection 全部 doc。
/// 線上抓最新並更新快取；離線/失敗退回上次快取；都沒有才回空（用 asset）。
final cloudAnnotationsProvider =
    FutureProvider<Map<String, Map<String, dynamic>>>((ref) async {
  const cacheKey = 'cache_annotations';
  if (ref.watch(firebaseReadyProvider)) {
    try {
      final fresh = await ref.watch(contentServiceProvider).fetchAll();
      await _writeCache(cacheKey, fresh);
      return fresh;
    } catch (_) {
      // 落到下方快取
    }
  }
  final cached = await _readCache(cacheKey);
  if (cached == null) return const {};
  return cached.map((k, v) =>
      MapEntry(k, (v as Map).cast<String, dynamic>()));
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

// ---- 聖經知識架構（時間軸/人物/平行對照/預表應驗；內容使用者親寫）----

final knowledgeRepositoryProvider =
    Provider((ref) => KnowledgeRepository());

/// 雲端知識資料（後台編輯的成果）。線上抓最新並更新快取；
/// 離線退回上次快取；都沒有回 null（用 asset）。
final cloudKnowledgeProvider =
    FutureProvider<Map<String, dynamic>?>((ref) async {
  const cacheKey = 'cache_knowledge';
  if (ref.watch(firebaseReadyProvider)) {
    try {
      final fresh =
          await ref.watch(contentServiceProvider).fetchKnowledge();
      if (fresh != null) await _writeCache(cacheKey, fresh);
      return fresh;
    } catch (_) {
      // 落到下方快取
    }
  }
  return _readCache(cacheKey);
});

/// 知識架構：**雲端優先、asset 為底**。後台存檔後 invalidate 即刷新。
final knowledgeProvider = FutureProvider<KnowledgeBase>((ref) async {
  final cloud = await ref.watch(cloudKnowledgeProvider.future);
  if (cloud != null) return KnowledgeBase.fromJson(cloud);
  return ref.watch(knowledgeRepositoryProvider).load();
});

// ---- 疑問 Q&A（全人工，無 AI）----

final qaServiceProvider = Provider((ref) => QaService());

/// 已審核公開問題（依分類過濾；分類為空＝全部）。
final approvedQuestionsProvider =
    FutureProvider.family<List<Question>, String>((ref, category) async {
  if (!ref.watch(firebaseReadyProvider)) return const [];
  return ref.watch(qaServiceProvider).approvedQuestions(category: category);
});

/// 我提出的問題（含待審／退回狀態）。
final myQuestionsProvider = FutureProvider<List<Question>>((ref) async {
  final user = ref.watch(authUserProvider).value;
  if (user == null) return const [];
  return ref.watch(qaServiceProvider).myQuestions(user.uid);
});

/// 待審問題佇列（管理者）。
final pendingQuestionsProvider = FutureProvider<List<Question>>((ref) async {
  if (!ref.watch(firebaseReadyProvider)) return const [];
  return ref.watch(qaServiceProvider).pendingQuestions();
});

/// 單一問題（詳情頁；invalidate 可刷新）。
final questionProvider =
    FutureProvider.family<Question?, String>((ref, id) async {
  if (!ref.watch(firebaseReadyProvider)) return null;
  return ref.watch(qaServiceProvider).getQuestion(id);
});

/// 我收藏的問題 id。
final savedQuestionIdsProvider = FutureProvider<Set<String>>((ref) async {
  final user = ref.watch(authUserProvider).value;
  if (user == null) return const {};
  return ref.watch(qaServiceProvider).savedIds(user.uid);
});

/// 我追蹤的問題（qid → 已讀時間）。
final followingQuestionsProvider =
    FutureProvider<Map<String, int>>((ref) async {
  final user = ref.watch(authUserProvider).value;
  if (user == null) return const {};
  return ref.watch(qaServiceProvider).followingMap(user.uid);
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

/// 全部禱告事項。
final allPrayersProvider = FutureProvider<List<Prayer>>(
    (ref) => ref.watch(databaseServiceProvider).getPrayers());

/// 全部信仰生活代辦事項。
final allTodosProvider = FutureProvider<List<Todo>>(
    (ref) => ref.watch(databaseServiceProvider).getTodos());

/// 禱告事項區塊在首頁的位置（使用者自選）：'top'＝繼續閱讀下面、
/// 'bottom'＝整頁下面。持久化到 SharedPreferences。
class PrayerPositionNotifier extends Notifier<String> {
  static const _key = 'prayer_position';

  @override
  String build() {
    _load();
    return 'bottom';
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_key);
      if (v == 'top' || v == 'bottom') state = v!;
    } catch (_) {}
  }

  Future<void> set(String v) async {
    state = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, v);
  }
}

final prayerPositionProvider =
    NotifierProvider<PrayerPositionNotifier, String>(
        PrayerPositionNotifier.new);

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
  Timer? _autoSyncTimer;

  @override
  String? build() {
    // 轉址登入回來（或任何時候從未登入變成已登入）→ 自動同步一次
    ref.listen(authUserProvider, (prev, next) {
      if (prev?.value == null && next.value != null) {
        syncNow();
      }
    });
    // 自動備份（Auto-Sync）：本地一有寫入（書籤/筆記/進度…），
    // debounce 10 秒後自動上傳雲端——換手機或移除 App 不丟信仰紀錄。
    ref.watch(databaseServiceProvider).onMutate = _scheduleAutoSync;
    ref.onDispose(() => _autoSyncTimer?.cancel());
    return null;
  }

  void _scheduleAutoSync() {
    if (Firebase.apps.isEmpty ||
        FirebaseAuth.instance.currentUser == null) {
      return; // 未登入：資料留在本地，登入後首次同步會補上
    }
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer(const Duration(seconds: 10), () {
      if (state == '同步中…') return;
      syncNow();
    });
  }

  /// 執行一次完整同步；結束後刷新所有標記 providers。
  Future<void> syncNow() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    state = '同步中…';
    try {
      // onStep 讓狀態列顯示卡在哪一步；timeout 讓卡住變成明確失敗（不再永遠轉圈）。
      state = await ref
          .read(syncServiceProvider)
          .syncAll(user.uid, onStep: (s) => state = s)
          .timeout(const Duration(seconds: 45),
              onTimeout: () => '同步逾時（卡在「${state ?? ''}」）。請把這行字告訴我。');
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

  /// Google 登入。網頁用 `signInWithPopup`（自帶視窗、會自己關，
  /// 比 signInWithRedirect 穩定——轉址常在跨網域儲存受限時掉進空白頁）。
  /// 官方 GIS 按鈕是主要路徑，這個是備用；兩者成功後都由 build() 的
  /// auth 監聽自動觸發同步。
  Future<void> signIn() async {
    if (_signingIn) return;
    _signingIn = true;
    state = '開啟 Google 登入視窗…';
    try {
      if (kIsWeb) {
        await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
        state = '登入成功，同步中…';
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
