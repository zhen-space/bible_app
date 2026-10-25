import '../models/models.dart';

enum PrayerListFilter { praying, all, answered, ended }

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
