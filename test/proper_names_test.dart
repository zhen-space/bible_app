import 'package:flutter_test/flutter_test.dart';
import 'package:bible_app/data/entities.dart';

void main() {
  group('專有名詞最長匹配', () {
    test('「以利亞撒」整體匹配，不會被「以利亞」切開', () {
      final hits = properNameMatches('祭司以利亞撒照耶和華所吩咐的行了');
      final eleazar = hits.where((h) => h.type == EntityType.person).toList();
      expect(eleazar, isNotEmpty);
      // 命中的那段長度應為 4（以利亞撒），不是 3（以利亞）
      final m = eleazar.first;
      expect(m.end - m.start, 4);
    });

    test('獨立的「以利亞」會被標記', () {
      final hits = properNameMatches('以利亞是先知');
      expect(hits.any((h) => h.end - h.start == 3), isTrue);
    });

    test('地名不會被內含的人名切開', () {
      final jacobsWell = properNameMatches('在那裡有雅各井');
      expect(jacobsWell, contains((start: 4, end: 7, type: EntityType.place)));
      expect(
        jacobsWell,
        isNot(contains((start: 4, end: 6, type: EntityType.person))),
      );

      final samaria = properNameMatches('有一個撒馬利亞的婦人');
      expect(samaria, contains((start: 3, end: 7, type: EntityType.place)));
      expect(
        samaria,
        isNot(contains((start: 4, end: 7, type: EntityType.person))),
      );

      const namedPlaces = <String>['約瑟門', '大衛城', '西奈山', '西乃山', '加利利海'];
      for (final name in namedPlaces) {
        final hits = properNameMatches(name);
        expect(hits, [
          (start: 0, end: name.length, type: EntityType.place),
        ], reason: '$name 應整體命中');
      }
    });

    test('較長人名不會被內含的短人名切開', () {
      const longerNames = <String>[
        '瑪挪亞',
        '以利亞實',
        '以利亞敬',
        '以利亞薩',
        '以利沙瑪',
        '約拿單',
        '約拿達',
      ];

      for (final name in longerNames) {
        final hits = properNameMatches(name);
        expect(hits, [
          (start: 0, end: name.length, type: EntityType.person),
        ], reason: '$name 應整體命中');
      }
    });
  });

  group('搜尋誤配過濾', () {
    test('搜「以利亞」時，只有「以利亞撒」的節算誤配（濾掉）', () {
      expect(queryOnlyInsideLongerName('於是摩西和祭司以利亞撒照著行', '以利亞'), isTrue);
    });

    test('搜「以利亞」時，真的有「以利亞」的節不算誤配（保留）', () {
      expect(queryOnlyInsideLongerName('以利亞對百姓說', '以利亞'), isFalse);
    });

    test('同一節同時有「以利亞」與「以利亞撒」→ 保留', () {
      expect(queryOnlyInsideLongerName('以利亞和以利亞撒都在', '以利亞'), isFalse);
    });

    test('非人名的查詢不受影響', () {
      expect(queryOnlyInsideLongerName('神愛世人', '愛'), isFalse);
    });

    test('搜短人名時，完整地名或其他人名應濾掉', () {
      expect(queryOnlyInsideLongerName('在那裡有雅各井', '雅各'), isTrue);
      expect(queryOnlyInsideLongerName('撒馬利亞的婦人', '馬利亞'), isTrue);
      expect(queryOnlyInsideLongerName('約拿單攻擊防營', '約拿'), isTrue);
      expect(queryOnlyInsideLongerName('以利沙瑪作首領', '以利沙'), isTrue);
      expect(queryOnlyInsideLongerName('瑪挪亞就祈求', '挪亞'), isTrue);
    });
  });
}
