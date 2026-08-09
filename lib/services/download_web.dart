import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// 網頁版：把文字內容做成 Blob，觸發瀏覽器下載。
/// 用系統字型，不受 App 內字型子集限制（使用者筆記的任意字都能正確顯示）。
bool downloadTextFile(String filename, String mimeType, String content) {
  final bytes = utf8.encode(content).toJS;
  final blob = web.Blob(
    [bytes].toJS,
    web.BlobPropertyBag(type: '$mimeType;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  anchor.click();
  web.URL.revokeObjectURL(url);
  return true;
}

/// 網頁版有檔案選取能力。
bool get canPickFile => true;

/// 網頁版：跳出系統選檔視窗，讀取文字檔內容。取消或失敗回 null。
Future<String?> pickTextFile() {
  final completer = Completer<String?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.txt,.md,text/plain,text/markdown';
  input.onchange = (web.Event _) {
    final files = input.files;
    if (files == null || files.length == 0) {
      if (!completer.isCompleted) completer.complete(null);
      return;
    }
    final reader = web.FileReader();
    reader.onload = (web.Event _) {
      final result = reader.result;
      final text =
          (result != null && result.isA<JSString>()) ? (result as JSString).toDart : null;
      if (!completer.isCompleted) completer.complete(text);
    }.toJS;
    reader.onerror = (web.Event _) {
      if (!completer.isCompleted) completer.complete(null);
    }.toJS;
    reader.readAsText(files.item(0)!);
  }.toJS;
  input.click();
  return completer.future;
}
