import 'package:flutter_test/flutter_test.dart';
import 'package:bible_app/data/entities.dart';

void main() {
  group('專有名詞最長匹配', () {
    test('「以利亞撒」整體匹配，不會被「以利亞」切開', () {
      final hits = properNameMatches('祭司以利亞撒照耶和華所吩咐的行了');
      final eleazar =
          hits.where((h) => h.type == EntityType.person).toList();
      expect(eleazar, isNotEmpty);
      // 命中的那段長度應為 4（以利亞撒），不是 3（以利亞）
      final m = eleazar.first;
      expect(m.end - m.start, 4);
    });

    test('獨立的「以利亞」會被標記', () {
      final hits = properNameMatches('以利亞是先知');
      expect(hits.any((h) => h.end - h.start == 3), isTrue);
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
      expect(
          queryOnlyInsideLongerName('以利亞和以利亞撒都在', '以利亞'), isFalse);
    });

    test('非人名的查詢不受影響', () {
      expect(queryOnlyInsideLongerName('神愛世人', '愛'), isFalse);
    });
  });
}
