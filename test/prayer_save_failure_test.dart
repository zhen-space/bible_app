import 'package:bible_app/models/models.dart';
import 'package:bible_app/providers/providers.dart';
import 'package:bible_app/screens/prayers_screen.dart';
import 'package:bible_app/services/database_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 不碰真 DB：第一次寫入丟例外（模擬儲存空間滿／IndexedDB 被擋），之後成功。
class _FlakyPrayerDatabaseService extends DatabaseService {
  int failuresLeft = 1;
  final saved = <Prayer>[];

  @override
  Future<int> savePrayer(Prayer p) async {
    if (failuresLeft > 0) {
      failuresLeft--;
      throw StateError('disk full');
    }
    saved.add(p);
    return saved.length;
  }

  @override
  Future<List<Prayer>> getPrayers() async => [
    for (var i = 0; i < saved.length; i++)
      Prayer(
        id: i + 1,
        title: saved[i].title,
        content: saved[i].content,
        category: saved[i].category,
      ),
  ];
}

void main() {
  testWidgets('375px 新增禱告寫入失敗：輸入保留、顯示錯誤，重試成功才關閉', (tester) async {
    SharedPreferences.setMockInitialValues({'prayers_list_filter': 'all'});
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = _FlakyPrayerDatabaseService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseServiceProvider.overrideWithValue(db),
          allPrayersProvider.overrideWith((ref) => db.getPrayers()),
          booksProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: PrayersScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('新增禱告事項'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '標題'), '為家人禱告');
    await tester.enterText(
      find.widgetWithText(TextField, '禱告內容'),
      '求主保守爸媽出入平安',
    );
    await tester.enterText(find.widgetWithText(TextField, '分類'), '家人');
    await tester.ensureVisible(find.widgetWithText(FilledButton, '儲存'));
    await tester.tap(find.widgetWithText(FilledButton, '儲存'));
    await tester.pumpAndSettle();

    // 失敗：sheet 仍在、文字仍在、明確提示，且按鈕變成重試。
    expect(tester.takeException(), isNull);
    expect(db.saved, isEmpty);
    expect(find.text('新增禱告事項'), findsWidgets);
    expect(find.text('為家人禱告'), findsOneWidget);
    expect(find.text('求主保守爸媽出入平安'), findsOneWidget);
    expect(find.text('儲存失敗，內容仍保留，請再試一次。'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '重試儲存'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(FilledButton, '重試儲存'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '重試儲存'));
    await tester.pumpAndSettle();

    // 重試成功：只寫入一次、sheet 關閉、清單出現新禱告事項。
    expect(db.saved, hasLength(1));
    expect(db.saved.single.title, '為家人禱告');
    expect(db.saved.single.content, '求主保守爸媽出入平安');
    expect(db.saved.single.category, '家人');
    expect(find.text('儲存失敗，內容仍保留，請再試一次。'), findsNothing);
    expect(find.widgetWithText(FilledButton, '重試儲存'), findsNothing);
    expect(find.widgetWithText(TextField, '禱告內容'), findsNothing);
    expect(find.text('為家人禱告'), findsOneWidget);
  });
}
