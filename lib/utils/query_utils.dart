/// 將使用者查詢拆成 AND 比對詞。
///
/// 除空白外，也接受中英文常用標點作為分隔符，避免中文輸入法輸出的
/// 逗號、頓號或全形空白把整段查詢誤當成單一詞。
List<String> queryTerms(String query) => query
    .trim()
    .toLowerCase()
    .split(RegExp(r'''[\s\u3000,，、;；.。!！?？"“”'‘’()（）\[\]【】<>《》]+'''))
    .where((term) => term.isNotEmpty)
    .toList(growable: false);
