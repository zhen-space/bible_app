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
