import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../services/bible_repository.dart';
import '../services/content_service.dart';
import '../services/content_workflow_service.dart';
import '../services/study_content_repository.dart';
import '../services/church_repository.dart';
import '../models/study_content.dart';
import '../models/church.dart';
import '../models/knowledge.dart';
import '../services/database_service.dart';
import '../services/qa_service.dart';
import '../services/sync_service.dart';

/// 管理者帳號（後台入口只對這個 Google 帳號顯示；
/// Firestore 規則端也用同一個 email 把關）。
const String kAdminEmail = 'zhen20091212@gmail.com';

final bibleRepositoryProvider = Provider((ref) => BibleRepository());
final databaseServiceProvider = Provider((ref) => DatabaseService());
// #8/#10 fail-closed：annotations/knowledge 只從雲端 Published 取得，**不再有**
// asset 倉庫 provider（移除舊的 annotationRepositoryProvider/knowledgeRepositoryProvider，
// 消除學生端 asset fallback 的殘留再進入點）。asset 檔僅供未來後台 seeding，非執行期讀取。

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
  final later = await db.getLaterVerses(args.bookId, args.chapter);
  return ChapterMarks(
      bookmarks: bookmarks, highlights: highlights, notes: notes, later: later);
});

class ChapterMarks {
  final Set<int> bookmarks;
  final Map<int, HighlightColor> highlights;
  final Map<int, Note> notes;
  final Set<int> later;

  const ChapterMarks({
    required this.bookmarks,
    required this.highlights,
    required this.notes,
    this.later = const {},
  });
}

/// 全部「稍後閱讀」項目。
final allLaterProvider = FutureProvider<List<Bookmark>>(
    (ref) => ref.watch(databaseServiceProvider).getAllLater());

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

/// 已完成章數（Chapter Completion，主動確認；全聖經 1,189 章）。
final readChapterCountProvider = FutureProvider<int>(
    (ref) => ref.watch(databaseServiceProvider).getReadChapterCount());

/// 某章是否已被使用者主動標記完成（讀經頁「完成本章」按鈕狀態）。
final chapterCompleteProvider =
    FutureProvider.family<bool, ({int bookId, int chapter})>((ref, args) {
  return ref
      .watch(databaseServiceProvider)
      .isChapterComplete(args.bookId, args.chapter);
});

/// 今天的日期字串 YYYY-MM-DD（每日經文 doc id）。
String _todayYmd() {
  final n = DateTime.now();
  return '${n.year.toString().padLeft(4, '0')}-'
      '${n.month.toString().padLeft(2, '0')}-'
      '${n.day.toString().padLeft(2, '0')}';
}

/// 官方每日經文（管理者發佈，Firestore `daily_verses`）。
/// **正式來源**；抓到就快取；離線退回快取。都沒有回 null（由 dailyVerseProvider 決定退路）。
final publishedDailyVerseProvider =
    FutureProvider<({int bookId, int chapter, int verse})?>((ref) async {
  final ymd = _todayYmd();
  final cacheKey = 'cache_daily_$ymd';
  ({int bookId, int chapter, int verse})? parse(Map<String, dynamic> m) {
    final b = m['book_id'], c = m['chapter'], v = m['verse'];
    if (b is int && c is int && v is int) {
      return (bookId: b, chapter: c, verse: v);
    }
    return null;
  }

  if (ref.watch(firebaseReadyProvider)) {
    try {
      final m = await ref.read(contentServiceProvider)
          .fetchPublishedDailyVerse(ymd);
      if (m != null) {
        await _writeCache(cacheKey, m);
        return parse(m);
      }
    } catch (_) {/* 離線/失敗 → 退快取 */}
  }
  final cached = await _readCache(cacheKey);
  if (cached != null) return parse(cached);
  return null;
});

/// 每日經文：**正式且唯一來源＝官方發佈（publishedDailyVerseProvider）**。
/// 沒有 Published 每日經文（或節位無效）時回 `null`＝「今日尚無經文」，
/// **不得 fallback 到本地經文池／隨機／AI**（#7 硬性要求，fail-closed）。
final dailyVerseProvider = FutureProvider<VerseRef?>((ref) async {
  final books = await ref.watch(booksProvider.future);
  final published = await ref.watch(publishedDailyVerseProvider.future);
  if (published == null) return null;
  final b = published.bookId, c = published.chapter, v = published.verse;
  // 防呆：發佈的節位需落在範圍內，否則視為無效內容（回 null，不 fallback）。
  if (b >= 1 &&
      b <= books.length &&
      c >= 1 &&
      c <= books[b - 1].chapters.length &&
      v >= 1 &&
      v <= books[b - 1].chapters[c - 1].length) {
    return VerseRef(
        bookId: b,
        chapter: c,
        verse: v,
        text: books[b - 1].chapters[c - 1][v - 1]);
  }
  return null;
});

final contentServiceProvider = Provider((ref) => ContentService());

/// 受管理內容發佈工作流（Draft→Review→Published→Rejected/Archived）。管理後台用。
final contentWorkflowServiceProvider = Provider(
    (ref) => ContentWorkflowService(FirebaseFirestore.instance));

/// Study Content（新版研讀內容）資料存取層。**下一輪 Student/Admin UI 依賴此契約。**
final studyContentRepositoryProvider = Provider((ref) => StudyContentRepository(
    FirebaseFirestore.instance, ref.watch(contentWorkflowServiceProvider)));

// ---- Church / Teacher R1 repositories + authorized providers ----

final churchRepositoryProvider =
    Provider((ref) => ChurchRepository(FirebaseFirestore.instance));
final teacherRepositoryProvider =
    Provider((ref) => TeacherRepository(FirebaseFirestore.instance));
final savedStudyContentRepositoryProvider =
    Provider((ref) => SavedStudyContentRepository(FirebaseFirestore.instance));

/// 目前使用者的 membership（無登入/無 doc → null）。
final myMembershipProvider = FutureProvider<Membership?>((ref) async {
  if (!ref.watch(firebaseReadyProvider)) return null;
  final uid = ref.watch(authUserProvider).value?.uid;
  if (uid == null) return null;
  return ref.watch(churchRepositoryProvider).fetchMembership(uid);
});

/// 目前授權快照（Active Membership → churchId，否則 none）。
final myAuthProvider = FutureProvider<StudentAuth>((ref) async {
  final m = await ref.watch(myMembershipProvider.future);
  return StudentAuth.from(m);
});

/// active churches（Picker）。
final activeChurchesProvider = FutureProvider<List<Church>>((ref) async {
  if (!ref.watch(firebaseReadyProvider)) return const [];
  return ref.watch(churchRepositoryProvider).fetchActiveChurches();
});

/// Admin：全部 churches（含 inactive）。
final adminAllChurchesProvider = FutureProvider<List<Church>>((ref) async {
  if (!ref.watch(firebaseReadyProvider)) return const [];
  return ref.watch(churchRepositoryProvider).fetchAllChurches();
});

/// Admin：待審 membership 佇列。
final adminPendingMembershipsProvider =
    FutureProvider<List<Membership>>((ref) async {
  if (!ref.watch(firebaseReadyProvider)) return const [];
  return ref.watch(churchRepositoryProvider).pendingMemberships();
});

/// **授權後**的研讀內容 universe（public ∪ active-church；無 fallback）。
final authorizedStudyContentProvider =
    FutureProvider<List<StudyContentItem>>((ref) async {
  if (!ref.watch(firebaseReadyProvider)) return const [];
  final auth = await ref.watch(myAuthProvider.future);
  return ref.watch(studyContentRepositoryProvider).fetchAuthorizedStudyContent(auth);
});

/// 授權後的主題。
final authorizedTopicsProvider = FutureProvider<List<StudyTopic>>((ref) async {
  if (!ref.watch(firebaseReadyProvider)) return const [];
  final auth = await ref.watch(myAuthProvider.future);
  return ref.watch(studyContentRepositoryProvider).fetchAuthorizedTopics(auth);
});

/// 授權後：某主題的研讀內容（已授權 universe narrow）。
final authorizedStudyContentByTopicProvider =
    FutureProvider.family<List<StudyContentItem>, String>((ref, topicId) async {
  if (!ref.watch(firebaseReadyProvider)) return const [];
  final auth = await ref.watch(myAuthProvider.future);
  return ref
      .watch(studyContentRepositoryProvider)
      .fetchAuthorizedByTopic(topicId, auth);
});

/// 目前使用者已儲存的研讀內容 id（relationship only）。
final savedStudyContentIdsProvider = FutureProvider<List<String>>((ref) async {
  if (!ref.watch(firebaseReadyProvider)) return const [];
  final uid = ref.watch(authUserProvider).value?.uid;
  if (uid == null) return const [];
  return ref.watch(savedStudyContentRepositoryProvider).savedIds(uid);
});

/// 已儲存研讀內容的 **live authorized resolve**（relationship 保留、access 現查）。
/// 回 (id, item?)：item==null ＝目前無權存取（revoked/未授權）→ UI 顯示「目前無法存取」。
final resolvedSavedStudyContentProvider =
    FutureProvider<List<({String id, StudyContentItem? item})>>((ref) async {
  if (!ref.watch(firebaseReadyProvider)) return const [];
  final ids = await ref.watch(savedStudyContentIdsProvider.future);
  final auth = await ref.watch(myAuthProvider.future);
  final repo = ref.watch(studyContentRepositoryProvider);
  final out = <({String id, StudyContentItem? item})>[];
  for (final id in ids) {
    out.add((id: id, item: await repo.fetchAuthorizedStudyContentById(id, auth)));
  }
  return out;
});

/// **授權後**的雲端註解（Reader 未來直接消費；public ∪ active-church，無 fallback）。
final authorizedAnnotationsProvider =
    FutureProvider<Map<String, Map<String, dynamic>>>((ref) async {
  if (!ref.watch(firebaseReadyProvider)) return const {};
  final auth = await ref.watch(myAuthProvider.future);
  return ref.watch(contentServiceProvider).fetchAuthorizedAnnotations(auth);
});

/// 學生端研讀內容：**只回 published+student**，沒有就空清單（**不 fallback knowledge/data**）。
final studentStudyContentProvider =
    FutureProvider<List<StudyContentItem>>((ref) async {
  if (!ref.watch(firebaseReadyProvider)) return const [];
  return ref.watch(studyContentRepositoryProvider).fetchStudentStudyContent();
});

/// 學生端研讀內容（依型別）。
final studentStudyContentByTypeProvider =
    FutureProvider.family<List<StudyContentItem>, StudyContentType>(
        (ref, type) async {
  if (!ref.watch(firebaseReadyProvider)) return const [];
  return ref
      .watch(studyContentRepositoryProvider)
      .fetchStudentStudyContentByType(type);
});

/// 學生端研讀內容（依主題）。
final studentStudyContentByTopicProvider =
    FutureProvider.family<List<StudyContentItem>, String>((ref, topicId) async {
  if (!ref.watch(firebaseReadyProvider)) return const [];
  return ref
      .watch(studyContentRepositoryProvider)
      .fetchStudentStudyContentByTopic(topicId);
});

/// 學生端可瀏覽的主題（published+student）。
final studentTopicsProvider = FutureProvider<List<StudyTopic>>((ref) async {
  if (!ref.watch(firebaseReadyProvider)) return const [];
  return ref.watch(studyContentRepositoryProvider).fetchStudentTopics();
});

// ---- Study Content Admin（後台；含未發佈，rules 限管理員）----

/// 目前登入的管理員 email（workflow 動作署名用）。
final adminEmailProvider = Provider<String>((ref) =>
    ref.watch(authUserProvider).value?.email ?? '');

final adminStudyContentListProvider =
    FutureProvider<List<AdminStudyRow>>((ref) async {
  if (!ref.watch(firebaseReadyProvider)) return const [];
  return ref.watch(studyContentRepositoryProvider).adminListContent();
});

final adminTopicListProvider =
    FutureProvider<List<AdminTopicRow>>((ref) async {
  if (!ref.watch(firebaseReadyProvider)) return const [];
  return ref.watch(studyContentRepositoryProvider).adminListTopics();
});

/// Q&A「回答依據」picker：只含已發佈 study content（含 internal，UI 標 visibility）。
final adminPublishedSourcesProvider =
    FutureProvider<List<StudyContentItem>>((ref) async {
  if (!ref.watch(firebaseReadyProvider)) return const [];
  return ref
      .watch(studyContentRepositoryProvider)
      .adminListPublishedForSources();
});

/// 後台每日經文清單（union mirror + workspace，依日期新到舊）。
final adminDailyVerseListProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  if (!ref.watch(firebaseReadyProvider)) return const [];
  return ref.watch(contentServiceProvider).adminListDailyVerses();
});

/// #9 檢索：只在 Published approved 內容上比對；不足→insufficientApprovedContent。
final qaRetrievalProvider = FutureProvider.family<QaRetrievalResult,
    ({String query, String category})>((ref, args) async {
  if (!ref.watch(firebaseReadyProvider)) return const QaRetrievalResult([]);
  return ref
      .watch(qaServiceProvider)
      .retrieveApproved(args.query, category: args.category);
});

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

/// 雲端內容層：annotations collection 的 **Published** doc（#8/#10 fail-closed）。
/// 線上只抓 `status=='published'`，抓到就把「已確認 Published 的版本」寫入快取；
/// 離線退回上次的 Published 快取；都沒有 → 空（**不得退回未驗證的 asset/草稿**）。
final cloudAnnotationsProvider =
    FutureProvider<Map<String, Map<String, dynamic>>>((ref) async {
  const cacheKey = 'cache_annotations_published';
  if (ref.watch(firebaseReadyProvider)) {
    try {
      final fresh = await ref.watch(contentServiceProvider).fetchAllPublished();
      await _writeCache(cacheKey, fresh); // 只快取 Published
      return fresh;
    } catch (_) {
      // 落到下方 Published 快取
    }
  }
  final cached = await _readCache(cacheKey);
  if (cached == null) return const {};
  return cached.map((k, v) =>
      MapEntry(k, (v as Map).cast<String, dynamic>()));
});

/// 整卷書的導讀＋統整（獨立標籤方格用）。**只用雲端 Published**；
/// 沒有就回 null（頁面顯示待填空白），**不退回 asset**（fail-closed）。
final bookAnnotationProvider =
    FutureProvider.family<BookAnnotation?, int>((ref, bookId) async {
  final cloud = await ref.watch(cloudAnnotationsProvider.future);
  final doc = cloud['book_$bookId'];
  if (doc == null) return null;
  return BookAnnotation.fromJson(ContentWorkflowService.payloadOf(doc));
});

/// 章導讀 + 該章的節註解。**只用雲端 Published**；沒有就空（fail-closed，不退回 asset）。
final chapterAnnotationProvider = FutureProvider.family<
    ({ChapterAnnotation? chapter, Map<int, VerseAnnotation> verses}),
    ({int bookId, int chapter})>((ref, args) async {
  final cloud = await ref.watch(cloudAnnotationsProvider.future);

  final cloudChapter = cloud['chapter_${args.bookId}_${args.chapter}'];
  final chapter = cloudChapter != null
      ? ChapterAnnotation.fromJson(ContentWorkflowService.payloadOf(cloudChapter))
      : null;

  final verses = <int, VerseAnnotation>{};
  final prefix = 'verse_${args.bookId}_${args.chapter}_';
  cloud.forEach((k, v) {
    if (k.startsWith(prefix)) {
      final verseNo = int.tryParse(k.substring(prefix.length));
      if (verseNo != null) {
        verses[verseNo] =
            VerseAnnotation.fromJson(ContentWorkflowService.payloadOf(v));
      }
    }
  });
  return (chapter: chapter, verses: verses);
});

/// 是否為管理者（同步；後台入口顯示條件）。**backward-compatible**：
/// legacy 單一 email 立即為真（不破壞現有登入）；custom claim 的判斷走
/// [adminClaimProvider]（非同步取 ID token）＋ [isAdminEffectiveProvider]。
final isAdminProvider = Provider<bool>((ref) {
  final user = ref.watch(authUserProvider).value;
  return user?.email == kAdminEmail;
});

/// custom claim `admin==true`（多管理員／角色的正式路徑）。取 ID token claims。
final adminClaimProvider = FutureProvider<bool>((ref) async {
  final user = ref.watch(authUserProvider).value;
  if (user == null) return false;
  try {
    final token = await user.getIdTokenResult();
    return token.claims?['admin'] == true;
  } catch (_) {
    return false;
  }
});

/// 有效管理者 = legacy email 或 custom claim。UI/後台入口可用此判斷。
final isAdminEffectiveProvider = FutureProvider<bool>((ref) async {
  if (ref.watch(isAdminProvider)) return true;
  return ref.watch(adminClaimProvider.future);
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

/// 雲端知識資料（**只用 Published**，#8/#10 fail-closed）。線上只在 knowledge/data
/// 為 Published 時抓，抓到就快取「已確認 Published 的版本」；離線退回上次 Published 快取；
/// 都沒有回 null（**不退回 asset**）。
final cloudKnowledgeProvider =
    FutureProvider<Map<String, dynamic>?>((ref) async {
  const cacheKey = 'cache_knowledge_published';
  if (ref.watch(firebaseReadyProvider)) {
    try {
      final fresh =
          await ref.watch(contentServiceProvider).fetchPublishedKnowledge();
      if (fresh != null) await _writeCache(cacheKey, fresh); // 只快取 Published
      return fresh;
    } catch (_) {
      // 落到下方 Published 快取
    }
  }
  return _readCache(cacheKey);
});

/// 知識架構：**只用雲端 Published**；沒有就回空（fail-closed，不退回 asset）。
final knowledgeProvider = FutureProvider<KnowledgeBase>((ref) async {
  final cloud = await ref.watch(cloudKnowledgeProvider.future);
  if (cloud == null) return KnowledgeBase.empty;
  return KnowledgeBase.fromJson(ContentWorkflowService.payloadOf(cloud));
});

// ---- 疑問 Q&A（全人工，無 AI）----

final qaServiceProvider = Provider((ref) => QaService());

/// **學生端可見的 Q&A ＝只有已發布（published）者**（依分類過濾；空＝全部）。
/// approved/reviewed 不算已發布；沒有已發布資料就是空清單（前端據此顯示
/// 「目前沒有已發布的解答」，不得以未發布內容或任何 AI 回答代替）。
final publishedQuestionsProvider =
    FutureProvider.family<List<Question>, String>((ref, category) async {
  if (!ref.watch(firebaseReadyProvider)) return const [];
  return ref.watch(qaServiceProvider).publishedQuestions(category: category);
});

/// 管理者：已回答但尚未發布的佇列（供發布）。非學生端來源。
final awaitingPublishQuestionsProvider =
    FutureProvider<List<Question>>((ref) async {
  if (!ref.watch(firebaseReadyProvider)) return const [];
  return ref.watch(qaServiceProvider).awaitingPublishQuestions();
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
/// 「最近刪除」的筆記（軟刪除）。
final deletedNotesProvider = FutureProvider<List<Note>>(
    (ref) => ref.watch(databaseServiceProvider).getDeletedNotes());
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

/// 讀經計畫 v2：各計畫已完成「讀經項目（章）」數，計畫列表進度條用。
final planItemDoneCountsProvider = FutureProvider<Map<String, int>>(
    (ref) => ref.watch(databaseServiceProvider).getPlanItemDoneCounts());

/// 讀經計畫 v2：單一計畫已完成的讀經項目集合（'b{book}_c{chapter}'）。
final planItemProgressProvider =
    FutureProvider.family<Set<String>, String>((ref, planId) {
  return ref.watch(databaseServiceProvider).getPlanItemProgress(planId);
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
