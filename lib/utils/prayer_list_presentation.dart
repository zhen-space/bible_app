import '../models/models.dart';

enum PrayerListFilter { praying, all, answered, ended }

PrayerListFilter decodePrayerListFilter(String? value) {
  for (final filter in PrayerListFilter.values) {
    if (filter.name == value) return filter;
  }
  return PrayerListFilter.praying;
}

List<Prayer> filterPrayersForList(
  Iterable<Prayer> values,
  PrayerListFilter filter,
) => switch (filter) {
  PrayerListFilter.praying =>
    values.where((prayer) => prayer.status == PrayerStatus.praying).toList(),
  PrayerListFilter.all => values.toList(),
  PrayerListFilter.answered =>
    values.where((prayer) => prayer.status == PrayerStatus.answered).toList(),
  PrayerListFilter.ended =>
    values.where((prayer) => prayer.status == PrayerStatus.ended).toList(),
};
