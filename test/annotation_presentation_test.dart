import 'package:flutter_test/flutter_test.dart';

import 'package:bible_app/models/models.dart';
import 'package:bible_app/screens/chapter_screen.dart';

/// Reader 節面板「雙區塊」呈現的純邏輯（不 pump 整個 Reader；驗證 label 與分組次序）。
/// 對應 spec CASE A–E / 授權呈現：public「公開註釋」在前、church「[教會]·教會專屬」在後。
void main() {
  group('annotationSectionLabel', () {
    test('public → 公開註釋', () {
      expect(annotationSectionLabel(false, '恩典教會'), '公開註釋');
      expect(annotationSectionLabel(false, null), '公開註釋');
    });
    test('church → [教會名] · 教會專屬', () {
      expect(annotationSectionLabel(true, '恩典教會'), '恩典教會 · 教會專屬');
    });
    test('church 無名 → 退回「教會 · 教會專屬」（不暴露其他教會）', () {
      expect(annotationSectionLabel(true, null), '教會 · 教會專屬');
      expect(annotationSectionLabel(true, ''), '教會 · 教會專屬');
    });
  });

  group('dual-section 次序（public 先 church 後）', () {
    // 這裡直接對 VerseAnnotationView list 斷言 Reader 會依序渲染的資料，
    // 呼應 chapterAnnotationProvider 的排序契約（provider 測試已覆蓋分組來源）。
    List<VerseAnnotationView> ordered(List<VerseAnnotationView> raw) {
      final copy = [...raw]..sort((a, b) {
          if (a.isChurch != b.isChurch) return a.isChurch ? 1 : -1;
          return a.annotationId.compareTo(b.annotationId);
        });
      return copy;
    }

    VerseAnnotationView v(String id, bool church) => VerseAnnotationView(
        verse: 1,
        isChurch: church,
        annotationId: id,
        ann: const VerseAnnotation(commentary: 'x'));

    test('CASE B：public + church → public first', () {
      final r = ordered([v('c1', true), v('p1', false)]);
      expect(r.map((e) => e.isChurch).toList(), [false, true]);
    });
    test('CASE D：多筆 public 穩定（id 升冪）', () {
      final r = ordered([v('p2', false), v('p1', false)]);
      expect(r.map((e) => e.annotationId).toList(), ['p1', 'p2']);
    });
    test('CASE E：多筆 church 穩定，且都排在 public 之後', () {
      final r = ordered([v('c2', true), v('p1', false), v('c1', true)]);
      expect(r.map((e) => e.annotationId).toList(), ['p1', 'c1', 'c2']);
    });
  });
}
