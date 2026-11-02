import 'package:bible_app/models/models.dart';
import 'package:bible_app/providers/providers.dart';
import 'package:bible_app/screens/prayers_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('375px 禱告篩選無結果可一鍵清除並顯示全部', (tester) async {
    SharedPreferences.setMockInitialValues({'prayers_list_filter': 'answered'});
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          allPrayersProvider.overrideWith(
            (ref) async => const [
              Prayer(id: 1, title: '為家人禱告', status: PrayerStatus.praying),
            ],
          ),
          booksProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: PrayersScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('還沒有已蒙應允的事項'), findsOneWidget);
    expect(find.text('為家人禱告'), findsNothing);

    await tester.tap(find.text('清除篩選'));
    await tester.pumpAndSettle();

    expect(find.text('為家人禱告'), findsOneWidget);
    expect(find.text('還沒有已蒙應允的事項'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('prayers_list_filter'), 'all');
  });
}
