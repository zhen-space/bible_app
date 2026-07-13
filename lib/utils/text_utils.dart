import 'package:flutter/material.dart';

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
