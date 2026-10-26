import 'dart:convert';

import 'package:bible_app/models/models.dart';
import 'package:bible_app/services/related_verse_search.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const books = [
    Book(
      id: 1,
      name: '測試書',
      abbr: '測',
      testament: 'nt',
      chapters: [
        [
          '你們要靠主常常喜樂。我再說，你們要喜樂。',
          '應當一無掛慮，只要凡事藉著禱告、祈求和感謝，將你們所要的告訴神。',
          '神所賜、出人意外的平安，必在基督耶穌裡保守你們的心懷意念。',
          '神愛世人，甚至將他的獨生子賜給他們。',
          '智慧必入你心；你的靈要以知識為美。',
          '無關的測試文字。',
          '你當剛強壯膽！不要懼怕，也不要驚惶。',
          '我必安然躺下睡覺，因為獨有你使我安然居住。',
          '復活在我，生命也在我；信我的人雖然死了，也必復活。',
          '你們作丈夫的，要愛你們的妻子。',
          '教養孩童，使他走當行的道。',
        ],
      ],
    ),
  ];

  test('精確經文永遠排在相關結果前面', () {
    final hits = RelatedVerseSearch.search(books, '神愛世人');

    expect(hits, isNotEmpty);
    expect(hits.first.isExact, isTrue);
    expect(hits.first.verse.verse, 4);
  });

  test('口語焦慮句能找到掛慮與平安經文', () {
    final hits = RelatedVerseSearch.search(books, '我很焦慮，不知道怎麼辦');
    final verses = hits.map((hit) => hit.verse.verse).toList();

    expect(verses, containsAll([2, 3]));
    expect(hits.every((hit) => !hit.isExact), isTrue);
    expect(hits.first.matchedTerms, isNotEmpty);
  });

  test('標點和空白不影響精確片語', () {
    final hits = RelatedVerseSearch.search(books, '神 愛，世人');

    expect(hits.first.isExact, isTrue);
    expect(hits.first.verse.verse, 4);
  });

  test('完全無關的經文不會混入結果', () {
    final hits = RelatedVerseSearch.search(books, '我最近很焦慮');

    expect(hits.any((hit) => hit.verse.verse == 6), isFalse);
  });

  test('迷惘的口語描述能找到智慧經文', () {
    final hits = RelatedVerseSearch.search(books, '我很迷惘，做決定沒有方向');

    expect(hits.any((hit) => hit.verse.verse == 5), isTrue);
  });

  test('需要勇氣的自然語句能找到剛強壯膽經文', () {
    final hits = RelatedVerseSearch.search(books, '我現在需要勇氣');

    expect(hits.any((hit) => hit.verse.verse == 7), isTrue);
  });

  test('生活處境語句能找到睡眠、哀傷、婚姻與教養經文', () {
    expect(
      RelatedVerseSearch.search(
        books,
        '最近一直睡不著',
      ).any((hit) => hit.verse.verse == 8),
      isTrue,
    );
    expect(
      RelatedVerseSearch.search(
        books,
        '失去親人很哀傷',
      ).any((hit) => hit.verse.verse == 9),
      isTrue,
    );
    expect(
      RelatedVerseSearch.search(
        books,
        '婚姻中要如何相愛',
      ).any((hit) => hit.verse.verse == 10),
      isTrue,
    );
    expect(
      RelatedVerseSearch.search(
        books,
        '如何教養孩子',
      ).any((hit) => hit.verse.verse == 11),
      isTrue,
    );
  });

  test('實際和合本中，焦慮口語句能找到腓立比書 4:6-7', () async {
    final raw = await rootBundle.loadString('assets/bible/cuv.json');
    final data = json.decode(raw) as Map<String, dynamic>;
    final corpus = (data['books'] as List)
        .map((book) => Book.fromJson(book as Map<String, dynamic>))
        .toList();

    final hits = RelatedVerseSearch.search(corpus, '最近很焦慮，不知道該怎麼辦');

    expect(
      hits.any(
        (hit) =>
            hit.verse.bookId == 50 &&
            hit.verse.chapter == 4 &&
            hit.verse.verse == 6,
      ),
      isTrue,
    );
    expect(
      hits.any(
        (hit) =>
            hit.verse.bookId == 50 &&
            hit.verse.chapter == 4 &&
            hit.verse.verse == 7,
      ),
      isTrue,
    );
  });
}
