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

  test('中文標點與全形空白可分詞並跨欄位命中', () {
    const fields = ['在患難中有平安', '以禱告交託', '存信心與盼望'];

    expect(matchesAllQueryTerms('平安，禱告', fields), isTrue);
    expect(matchesAllQueryTerms('信心、盼望', fields), isTrue);
    expect(matchesAllQueryTerms('平安　禱告', fields), isTrue);
  });

  test('只有標點的查詢不命中', () {
    expect(matchesAllQueryTerms('，、；！？。', ['任何內容']), isFalse);
  });

  test('命中預覽依查詢順序取正文中的第一個實際命中句', () {
    expect(queryMatchSentence('平安，禱告', '先安靜等候。即使患難仍有平安。最後以禱告交託。'), '即使患難仍有平安。');
    expect(
      queryMatchSentence('GRACE', 'Saved by Grace. Keep walking.'),
      'Saved by Grace. Keep walking.',
    );
    expect(queryMatchSentence('標籤命中', '正文沒有這個詞'), isNull);
  });
}
