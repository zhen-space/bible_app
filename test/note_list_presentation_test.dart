import 'package:bible_app/models/models.dart';
import 'package:bible_app/utils/note_list_presentation.dart';
import 'package:flutter_test/flutter_test.dart';

Note note({
  required int id,
  required int book,
  required int chapter,
  required int verse,
  required String title,
  required int created,
  required int updated,
}) => Note(
  id: id,
  bookId: book,
  chapter: chapter,
  verse: verse,
  title: title,
  content: '',
  createdAt: created,
  updatedAt: updated,
);

void main() {
  final notes = [
    note(
      id: 1,
      book: 43,
      chapter: 3,
      verse: 16,
      title: '愛',
      created: 10,
      updated: 30,
    ),
    note(
      id: 2,
      book: 1,
      chapter: 1,
      verse: 1,
      title: '',
      created: 30,
      updated: 10,
    ),
    note(
      id: 3,
      book: 19,
      chapter: 23,
      verse: 1,
      title: '平安',
      created: 20,
      updated: 20,
    ),
  ];

  test('支援最近編輯、建立、標題與經文位置排序', () {
    expect(sortNotesForList(notes, NoteSortOrder.updated).map((n) => n.id), [
      1,
      3,
      2,
    ]);
    expect(sortNotesForList(notes, NoteSortOrder.created).map((n) => n.id), [
      2,
      3,
      1,
    ]);
    expect(sortNotesForList(notes, NoteSortOrder.title).map((n) => n.id), [
      3,
      1,
      2,
    ]);
    expect(sortNotesForList(notes, NoteSortOrder.scripture).map((n) => n.id), [
      2,
      3,
      1,
    ]);
  });

  test('排序偏好可從儲存值安全還原', () {
    expect(decodeNoteSortOrder('scripture'), NoteSortOrder.scripture);
    expect(decodeNoteSortOrder('unknown'), NoteSortOrder.updated);
    expect(decodeNoteSortOrder(null), NoteSortOrder.updated);
  });

  test('筆記搜尋不分英文大小寫且支援多詞交集', () {
    final searchable = [
      Note(
        id: 10,
        bookId: 50,
        chapter: 4,
        verse: 6,
        title: 'Prayer Notes',
        content: '不要掛慮，只要禱告',
        tags: '平安,靈修',
        createdAt: 10,
        updatedAt: 10,
      ),
      Note(
        id: 11,
        bookId: 43,
        chapter: 14,
        verse: 27,
        title: '平安',
        content: '我留下平安給你們',
        tags: '應許',
        createdAt: 20,
        updatedAt: 20,
      ),
    ];

    expect(searchNotesForList(searchable, 'PRAYER').single.id, 10);
    expect(searchNotesForList(searchable, '平安 靈修').single.id, 10);
    expect(
      searchNotesForList(
        searchable,
        '腓立比 4:6',
        extraText: (note) => note.id == 10 ? '腓立比書 腓立比 4:6' : '約翰福音 14:27',
      ).single.id,
      10,
    );
    expect(searchNotesForList(searchable, '不存在'), isEmpty);
  });

  test('日期分組與清單日期顯示符合今天、昨天、近期與月份', () {
    final now = DateTime(2026, 10, 25, 15, 30);

    expect(
      noteDateSection(DateTime(2026, 10, 25, 9).millisecondsSinceEpoch, now),
      '今天',
    );
    expect(
      noteDateSection(DateTime(2026, 10, 24).millisecondsSinceEpoch, now),
      '昨天',
    );
    expect(
      noteDateSection(DateTime(2026, 10, 20).millisecondsSinceEpoch, now),
      '最近 7 天',
    );
    expect(
      noteDateSection(DateTime(2026, 8, 1).millisecondsSinceEpoch, now),
      '8 月',
    );
    expect(
      compactNoteDate(DateTime(2026, 10, 25, 9, 5).millisecondsSinceEpoch, now),
      '09:05',
    );
  });

  test('舊資料沒有更新時間時改用建立時間', () {
    final legacy = note(
      id: 4,
      book: 40,
      chapter: 5,
      verse: 9,
      title: '舊筆記',
      created: 99,
      updated: 0,
    );

    expect(noteListTimestamp(legacy), 99);
    expect(
      sortNotesForList([...notes, legacy], NoteSortOrder.updated).first.id,
      4,
    );
  });
}
