import '../models/models.dart';

enum PrayerListFilter { praying, all, answered, ended }

enum PrayerSortOrder { category, recent }

PrayerListFilter decodePrayerListFilter(String? value) {
  for (final filter in PrayerListFilter.values) {
    if (filter.name == value) return filter;
  }
  return PrayerListFilter.praying;
}

PrayerSortOrder decodePrayerSortOrder(String? value) {
  for (final order in PrayerSortOrder.values) {
    if (order.name == value) return order;
  }
  return PrayerSortOrder.category;
}

List<Prayer> sortPrayersForList(
  Iterable<Prayer> values,
  PrayerSortOrder order,
) {
  final prayers = values.toList();
  prayers.sort((a, b) {
    if (order == PrayerSortOrder.recent) {
      final byUpdated = b.updatedAt.compareTo(a.updatedAt);
      if (byUpdated != 0) return byUpdated;
      return b.createdAt.compareTo(a.createdAt);
    }
    final byCategory = a.category.compareTo(b.category);
    if (byCategory != 0) return byCategory;
    final bySubcategory = a.subcategory.compareTo(b.subcategory);
    if (bySubcategory != 0) return bySubcategory;
    return b.createdAt.compareTo(a.createdAt);
  });
  return prayers;
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
