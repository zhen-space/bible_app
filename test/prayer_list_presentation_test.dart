import 'package:bible_app/models/models.dart';
import 'package:bible_app/utils/prayer_list_presentation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const prayers = [
    Prayer(id: 1, title: 'A', status: PrayerStatus.praying),
    Prayer(id: 2, title: 'B', status: PrayerStatus.answered),
    Prayer(id: 3, title: 'C', status: PrayerStatus.ended),
  ];

  test('篩選偏好可安全還原，未知值回到禱告中', () {
    expect(decodePrayerListFilter('all'), PrayerListFilter.all);
    expect(decodePrayerListFilter('answered'), PrayerListFilter.answered);
    expect(decodePrayerListFilter('ended'), PrayerListFilter.ended);
    expect(decodePrayerListFilter('unknown'), PrayerListFilter.praying);
    expect(decodePrayerListFilter(null), PrayerListFilter.praying);
  });

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

  test('分類建議會去重排序，子分類只顯示目前分類', () {
    const values = [
      Prayer(category: '家庭', subcategory: '父母'),
      Prayer(category: '教會', subcategory: '小組'),
      Prayer(category: '家庭', subcategory: '孩子'),
      Prayer(category: '家庭', subcategory: '孩子'),
      Prayer(category: '  ', subcategory: '忽略'),
    ];
    expect(prayerCategorySuggestions(values), ['家庭', '教會']);
    expect(prayerSubcategorySuggestions(values, '家庭'), ['孩子', '父母']);
  });
}
