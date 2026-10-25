import 'package:bible_app/utils/text_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('多關鍵詞搜尋可跨欄位命中', () {
    expect(matchesAllQueryTerms('平安 禱告', ['在患難中有平安', '以禱告交託']), isTrue);
    expect(matchesAllQueryTerms('平安 感恩', ['在患難中有平安', '以禱告交託']), isFalse);
  });

  test('英文搜尋不分大小寫且空白查詢不命中', () {
    expect(matchesAllQueryTerms('GRACE', ['Saved by grace']), isTrue);
    expect(matchesAllQueryTerms('   ', ['anything']), isFalse);
  });
}
