import 'package:flutter/material.dart';

import '../data/entities.dart';

/// 取出內容中「包含關鍵詞的那一句」。
/// 以句末標點（。！？；換行）為界；找不到關鍵詞時回傳開頭一段。
String sentenceWithMatch(String content, String query) {
  final q = query.trim();
  if (q.isEmpty) return content;
  final idx = content.indexOf(q);
  if (idx < 0) {
    return content.length <= 60 ? content : '${content.substring(0, 60)}…';
  }
  final seps = RegExp(r'[。！？；\n]');
  var start = 0;
  for (final m in seps.allMatches(content)) {
    if (m.end <= idx) {
      start = m.end;
    } else {
      break;
    }
  }
  final after = seps.firstMatch(content.substring(idx + q.length));
  final end =
      after == null ? content.length : idx + q.length + after.end;
  return content.substring(start, end).trim();
}

/// 把 [text] 中出現的 [query] 高亮（粗體＋主色），回傳 spans。
List<TextSpan> highlightSpans(
    BuildContext context, String text, String query,
    {TextStyle? style}) {
  final q = query.trim();
  final base = style ?? DefaultTextStyle.of(context).style;
  if (q.isEmpty || !text.contains(q)) {
    return [TextSpan(text: text, style: base)];
  }
  final hl = base.copyWith(
    fontWeight: FontWeight.w700,
    color: Theme.of(context).colorScheme.primary,
  );
  final spans = <TextSpan>[];
  var rest = text;
  while (true) {
    final i = rest.indexOf(q);
    if (i < 0) {
      if (rest.isNotEmpty) spans.add(TextSpan(text: rest, style: base));
      break;
    }
    if (i > 0) spans.add(TextSpan(text: rest.substring(0, i), style: base));
    spans.add(TextSpan(text: q, style: hl));
    rest = rest.substring(i + q.length);
  }
  return spans;
}

/// 把 [text] 中已知的人名／地名畫上「私名號」（專名號，底線），
/// 並可另外把 [query] 關鍵詞加粗高亮（搜尋用）。名字邊界走最長匹配
/// （「以利亞撒」整體標記，不會被「以利亞」切開）。未收進索引的名字不標。
List<TextSpan> properNameSpans(BuildContext context, String text,
    {String query = '', TextStyle? style}) {
  final base = style ?? DefaultTextStyle.of(context).style;
  if (text.isEmpty) return [TextSpan(text: text, style: base)];
  final primary = Theme.of(context).colorScheme.primary;

  // 每字元：是否專名、是否關鍵詞命中
  final isName = List<bool>.filled(text.length, false);
  for (final m in properNameMatches(text)) {
    for (var k = m.start; k < m.end; k++) {
      isName[k] = true;
    }
  }
  final isHit = List<bool>.filled(text.length, false);
  final q = query.trim();
  if (q.isNotEmpty) {
    var idx = text.indexOf(q);
    while (idx >= 0) {
      for (var k = idx; k < idx + q.length; k++) {
        isHit[k] = true;
      }
      idx = text.indexOf(q, idx + q.length);
    }
  }

  TextStyle styleAt(int i) {
    var s = base;
    if (isName[i]) {
      s = s.copyWith(
        decoration: TextDecoration.underline,
        decorationColor: primary.withValues(alpha: 0.55),
        decorationThickness: 1.4,
      );
    }
    if (isHit[i]) {
      s = s.copyWith(fontWeight: FontWeight.w700, color: primary);
    }
    return s;
  }

  int key(int i) => (isName[i] ? 2 : 0) + (isHit[i] ? 1 : 0);

  final spans = <TextSpan>[];
  var start = 0;
  for (var i = 1; i <= text.length; i++) {
    if (i == text.length || key(i) != key(start)) {
      spans.add(TextSpan(text: text.substring(start, i), style: styleAt(start)));
      start = i;
    }
  }
  return spans;
}
