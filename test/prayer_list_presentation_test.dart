import 'package:bible_app/models/models.dart';
import 'package:bible_app/utils/prayer_list_presentation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const prayers = [
    Prayer(id: 1, title: 'A', status: PrayerStatus.praying),
    Prayer(id: 2, title: 'B', status: PrayerStatus.answered),
    Prayer(id: 3, title: 'C', status: PrayerStatus.ended),
  ];

  test('禱告狀態篩選回傳對應項目', () {
    expect(
      filterPrayersForList(
        prayers,
        PrayerListFilter.praying,
      ).map((prayer) => prayer.id),
      [1],
    );
    expect(
      filterPrayersForList(
        prayers,
        PrayerListFilter.answered,
      ).map((prayer) => prayer.id),
      [2],
    );
    expect(
      filterPrayersForList(
        prayers,
        PrayerListFilter.ended,
      ).map((prayer) => prayer.id),
      [3],
    );
    expect(filterPrayersForList(prayers, PrayerListFilter.all), hasLength(3));
  });
}
