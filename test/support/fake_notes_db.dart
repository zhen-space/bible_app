import 'dart:async';

import 'package:bible_app/models/models.dart';
import 'package:bible_app/services/database_service.dart';

/// 不碰真 DB：記憶體筆記清單，模擬 DB 層語意（saveNoteFull：id 為 null＝新增一則、
/// 有 id＝只改那一則；softDeleteNoteById：移到最近刪除）。`failOnCalls` 指定第幾次
/// 寫入丟例外——DB 層這些操作都是單一陳述或交易，失敗＝資料完全沒變。
class FakeNotesDb extends DatabaseService {
  FakeNotesDb(this.rows);
  final List<Note> rows;
  int calls = 0;
  int clock = 1000;
  final failOnCalls = <int>{};
  final log = <String>[];

  void _maybeFail() {
    calls++;
    if (failOnCalls.contains(calls)) throw StateError('write failed');
  }

  List<Note> _live(int b, int c) {
    final out =
        rows
            .where((r) => r.bookId == b && r.chapter == c && !r.isDeleted)
            .toList()
          ..sort((a, z) => z.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  @override
  Future<Map<int, List<Note>>> getChapterNoteLists(int b, int c) async {
    final out = <int, List<Note>>{};
    for (final n in _live(b, c)) {
      out.putIfAbsent(n.verse, () => []).add(n);
    }
    return out;
  }

  @override
  Future<List<Note>> getVerseNotes(int b, int c, int v) async {
    _maybeFailRead();
    return _live(b, c).where((n) => n.verse == v).toList();
  }

  @override
  Future<int> saveNoteFull(Note note) async {
    _maybeFail();
    final now = ++clock;
    if (note.id == null) {
      final id = rows.fold<int>(0, (m, r) => r.id! > m ? r.id! : m) + 1;
      log.add('insert $id');
      rows.add(
        Note(
          id: id,
          bookId: note.bookId,
          chapter: note.chapter,
          verse: note.verse,
          title: note.title,
          content: note.content,
          tags: note.tags,
          refs: note.refs,
          createdAt: now,
          updatedAt: now,
        ),
      );
      return id;
    }
    log.add('update ${note.id}');
    final i = rows.indexWhere((r) => r.id == note.id);
    rows[i] = Note(
      id: note.id,
      bookId: note.bookId,
      chapter: note.chapter,
      verse: note.verse,
      title: note.title,
      content: note.content,
      tags: note.tags,
      refs: note.refs,
      createdAt: rows[i].createdAt,
      updatedAt: now,
    );
    return note.id!;
  }

  @override
  Future<void> softDeleteNoteById(int id) async {
    _maybeFail();
    log.add('soft $id');
    final i = rows.indexWhere((r) => r.id == id);
    final n = rows[i];
    rows[i] = Note(
      id: n.id,
      bookId: n.bookId,
      chapter: n.chapter,
      verse: n.verse,
      title: n.title,
      content: n.content,
      tags: n.tags,
      refs: n.refs,
      deletedAt: ++clock,
      createdAt: n.createdAt,
      updatedAt: clock,
    );
  }

  // 舊的整節 API 不應再被讀經頁用來寫筆記（會改到／刪到同節別則）。
  @override
  Future<void> saveNote(
    int b,
    int c,
    int v,
    String content, {
    String tags = '',
  }) async {
    log.add('legacy saveNote');
  }

  @override
  Future<void> deleteNote(int b, int c, int v) async {
    log.add('legacy deleteNote');
  }

  /// 讀個人標記（螢光筆／書籤／稍後讀／筆記）時丟例外，模擬本機 DB 暫時無法讀取。
  bool failMarks = false;

  void _maybeFailRead() {
    if (failMarks) throw StateError('read failed');
  }

  /// 已存的書籤／螢光筆／稍後讀（key＝`book:chapter:verse`）。
  final bookmarks = <String>{};
  final highlights = <String, HighlightColor>{};
  final later = <String>{};

  /// 標記寫入（setBookmark／setHighlight／setLater）的第幾次丟例外（與筆記分開計數）。
  int markCalls = 0;
  final failMarkCalls = <int>{};

  /// 設了就讓標記寫入卡在這裡，直到測試 complete（模擬寫入進行中）。
  Completer<void>? markGate;

  static String _k(int b, int c, int v) => '$b:$c:$v';

  Future<void> _markWrite(String entry, void Function() apply) async {
    markCalls++;
    log.add(entry);
    final gate = markGate;
    if (gate != null) await gate.future;
    if (failMarkCalls.contains(markCalls)) throw StateError('write failed');
    apply();
  }

  Map<String, Object> _pick(String key) {
    final p = key.split(':').map(int.parse).toList();
    return {'b': p[0], 'c': p[1], 'v': p[2]};
  }

  @override
  Future<Set<int>> getBookmarkedVerses(int b, int c) async {
    _maybeFailRead();
    return {
      for (final k in bookmarks)
        if (k.startsWith('$b:$c:')) int.parse(k.split(':')[2]),
    };
  }

  @override
  Future<Map<int, HighlightColor>> getChapterHighlights(int b, int c) async {
    _maybeFailRead();
    return {
      for (final e in highlights.entries)
        if (e.key.startsWith('$b:$c:')) int.parse(e.key.split(':')[2]): e.value,
    };
  }

  @override
  Future<Set<int>> getLaterVerses(int b, int c) async {
    _maybeFailRead();
    return {
      for (final k in later)
        if (k.startsWith('$b:$c:')) int.parse(k.split(':')[2]),
    };
  }

  @override
  Future<void> toggleBookmark(int b, int c, int v) async {
    log.add('legacy toggleBookmark');
  }

  @override
  Future<void> setBookmark(int b, int c, int v, bool bookmarked) =>
      _markWrite('bookmark $bookmarked', () {
        bookmarked ? bookmarks.add(_k(b, c, v)) : bookmarks.remove(_k(b, c, v));
      });

  @override
  Future<void> setHighlight(int b, int c, int v, HighlightColor? color) =>
      _markWrite('highlight ${color?.name}', () {
        color == null
            ? highlights.remove(_k(b, c, v))
            : highlights[_k(b, c, v)] = color;
      });

  @override
  Future<void> setLater(int b, int c, int v, bool value) =>
      _markWrite('later $value', () {
        value ? later.add(_k(b, c, v)) : later.remove(_k(b, c, v));
      });

  @override
  Future<List<Bookmark>> getAllLater() async => [];

  @override
  Future<void> markChapterRead(int b, int c) async {}

  @override
  Future<bool> isChapterComplete(int b, int c) async => false;

  @override
  Future<List<Bookmark>> getAllBookmarks() async => [
    for (final k in bookmarks)
      Bookmark(
        bookId: _pick(k)['b'] as int,
        chapter: _pick(k)['c'] as int,
        verse: _pick(k)['v'] as int,
        createdAt: 0,
      ),
  ];

  @override
  Future<List<Highlight>> getAllHighlights() async => [
    for (final e in highlights.entries)
      Highlight(
        bookId: _pick(e.key)['b'] as int,
        chapter: _pick(e.key)['c'] as int,
        verse: _pick(e.key)['v'] as int,
        color: e.value,
        createdAt: 0,
      ),
  ];

  @override
  Future<List<Note>> getAllNotes() async =>
      rows.where((r) => !r.isDeleted).toList();
}
