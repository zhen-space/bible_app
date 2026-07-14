import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/knowledge.dart';

/// 載入聖經知識架構資料（asset，可插拔、可缺）。
/// 之後若要雲端後台編輯，可仿 annotations 加 cloud 覆蓋層。
class KnowledgeRepository {
  KnowledgeBase? _cache;

  Future<KnowledgeBase> load() async {
    if (_cache != null) return _cache!;
    try {
      final raw =
          await rootBundle.loadString('assets/knowledge/knowledge.json');
      _cache = KnowledgeBase.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      _cache = KnowledgeBase.empty; // 缺檔或壞檔都不擋 App
    }
    return _cache!;
  }
}
