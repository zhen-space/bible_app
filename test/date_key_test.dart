import 'package:flutter_test/flutter_test.dart';
import 'package:bible_app/utils/date_key.dart';

/// §A5：權威日期鍵＝Asia/Taipei（UTC+8），與裝置時區無關。
void main() {
  test('UTC 跨日界：16:00Z 已是台北隔日', () {
    // 2026-01-01T16:00Z = 2026-01-02T00:00 台北
    expect(taipeiYmd(DateTime.utc(2026, 1, 1, 16, 0)), '2026-01-02');
    // 2026-01-01T15:59Z = 2026-01-01T23:59 台北（仍當日）
    expect(taipeiYmd(DateTime.utc(2026, 1, 1, 15, 59)), '2026-01-01');
  });

  test('裝置時區不影響結果：同一 instant 不論 local 皆同台北日', () {
    final instant = DateTime.utc(2026, 3, 10, 20, 30); // 台北 2026-03-11 04:30
    // 用不同本地表示的同一時刻（toUtc 後相同）→ 同一台北日鍵。
    expect(taipeiYmd(instant), '2026-03-11');
    expect(taipeiYmd(instant.toLocal()), '2026-03-11');
  });

  test('格式為 YYYY-MM-DD（補零）', () {
    expect(taipeiYmd(DateTime.utc(2026, 2, 3, 4, 5)), '2026-02-03');
  });
}
