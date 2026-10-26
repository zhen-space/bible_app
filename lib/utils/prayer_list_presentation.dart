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

List<String> prayerCategorySuggestions(Iterable<Prayer> values) {
  final categories = {
    for (final prayer in values)
      if (prayer.category.trim().isNotEmpty) prayer.category.trim(),
  }.toList()..sort();
  return categories;
}

List<String> prayerSubcategorySuggestions(
  Iterable<Prayer> values,
  String category,
) {
  final selected = category.trim();
  final subcategories = {
    for (final prayer in values)
      if (prayer.category.trim() == selected &&
          prayer.subcategory.trim().isNotEmpty)
        prayer.subcategory.trim(),
  }.toList()..sort();
  return subcategories;
}
