/// 人物／地點／事件索引（白板「三、搜尋與索引」）。
/// 只放「名稱」與別名——點選後以全文搜尋找出該名稱在聖經中的所有出現處，
/// 因此不需預先建立（可能出錯的）節位清單，也方便日後增補。
library;

enum EntityType { person, place, event }

class BibleEntity {
  final String name;
  final EntityType type;
  final List<String> aka; // 別名／同義詞（一起比對，但搜尋用主名）

  const BibleEntity(this.name, this.type, {this.aka = const []});
}

const List<BibleEntity> entities = [
  // 人物
  BibleEntity('亞當', EntityType.person),
  BibleEntity('夏娃', EntityType.person),
  BibleEntity('挪亞', EntityType.person),
  BibleEntity('亞伯拉罕', EntityType.person, aka: ['亞伯蘭']),
  BibleEntity('以撒', EntityType.person),
  BibleEntity('雅各', EntityType.person, aka: ['以色列']),
  BibleEntity('約瑟', EntityType.person),
  BibleEntity('摩西', EntityType.person),
  BibleEntity('亞倫', EntityType.person),
  BibleEntity('約書亞', EntityType.person),
  BibleEntity('基甸', EntityType.person),
  BibleEntity('參孫', EntityType.person),
  BibleEntity('路得', EntityType.person),
  BibleEntity('撒母耳', EntityType.person),
  BibleEntity('掃羅', EntityType.person),
  BibleEntity('大衛', EntityType.person),
  BibleEntity('所羅門', EntityType.person),
  BibleEntity('以利亞', EntityType.person),
  BibleEntity('以利亞撒', EntityType.person), // Eleazar，勿與「以利亞」混（最長匹配靠它）
  BibleEntity('以利沙', EntityType.person),
  BibleEntity('以賽亞', EntityType.person),
  BibleEntity('耶利米', EntityType.person),
  BibleEntity('但以理', EntityType.person),
  BibleEntity('約拿', EntityType.person),
  BibleEntity('以斯帖', EntityType.person),
  BibleEntity('尼希米', EntityType.person),
  BibleEntity('以斯拉', EntityType.person),
  BibleEntity('約伯', EntityType.person),
  BibleEntity('耶穌', EntityType.person, aka: ['基督', '主耶穌']),
  BibleEntity('馬利亞', EntityType.person),
  BibleEntity('約翰', EntityType.person, aka: ['施洗約翰']),
  BibleEntity('彼得', EntityType.person, aka: ['西門']),
  BibleEntity('保羅', EntityType.person, aka: ['掃羅']),
  BibleEntity('猶大', EntityType.person),
  BibleEntity('多馬', EntityType.person),
  BibleEntity('提摩太', EntityType.person),
  BibleEntity('馬大', EntityType.person),
  // 地點
  BibleEntity('伊甸園', EntityType.place),
  BibleEntity('埃及', EntityType.place),
  BibleEntity('迦南', EntityType.place),
  BibleEntity('西奈', EntityType.place, aka: ['西乃']),
  BibleEntity('耶路撒冷', EntityType.place),
  BibleEntity('伯利恆', EntityType.place),
  BibleEntity('拿撒勒', EntityType.place),
  BibleEntity('加利利', EntityType.place),
  BibleEntity('約旦河', EntityType.place, aka: ['約但河']),
  BibleEntity('巴比倫', EntityType.place),
  BibleEntity('尼尼微', EntityType.place),
  BibleEntity('大馬士革', EntityType.place),
  BibleEntity('羅馬', EntityType.place),
  BibleEntity('哥林多', EntityType.place),
  BibleEntity('以弗所', EntityType.place),
  // 事件
  BibleEntity('創造', EntityType.event),
  BibleEntity('洪水', EntityType.event, aka: ['方舟']),
  BibleEntity('出埃及', EntityType.event),
  BibleEntity('逾越節', EntityType.event),
  BibleEntity('十誡', EntityType.event),
  BibleEntity('被擄', EntityType.event),
  BibleEntity('降生', EntityType.event, aka: ['道成肉身']),
  BibleEntity('受洗', EntityType.event),
  BibleEntity('登山寶訓', EntityType.event),
  BibleEntity('最後的晚餐', EntityType.event),
  BibleEntity('釘十字架', EntityType.event, aka: ['十字架']),
  BibleEntity('復活', EntityType.event),
  BibleEntity('五旬節', EntityType.event, aka: ['聖靈降臨']),
];

/// 依查詢字比對名稱或別名（子字串）。
List<BibleEntity> searchEntities(String query) {
  final q = query.trim();
  if (q.isEmpty) return const [];
  return entities
      .where((e) =>
          e.name.contains(q) ||
          q.contains(e.name) ||
          e.aka.any((a) => a.contains(q) || q.contains(a)))
      .toList();
}

// ────────────────────────────────────────────────────────────────
// 專有名詞（人名＋地名，含別名）：供「私名號」標記與最長匹配用。
// 事件不算專名。名字未收進索引者不會被標記或斷界——增補這裡即可擴大覆蓋。

class ProperName {
  final String text;
  final EntityType type; // person / place
  const ProperName(this.text, this.type);
}

/// 依長度由長到短排序，讓最長匹配（「以利亞撒」勝過「以利亞」）優先命中。
final List<ProperName> properNames = () {
  final list = <ProperName>[];
  for (final e in entities) {
    if (e.type == EntityType.event) continue;
    list.add(ProperName(e.name, e.type));
    for (final a in e.aka) {
      list.add(ProperName(a, e.type));
    }
  }
  list.sort((a, b) => b.text.length.compareTo(a.text.length));
  return list;
}();

typedef NameHit = ({int start, int end, EntityType type});

/// 掃描 [text]，回傳不重疊的專有名詞出現處（最長優先）。
List<NameHit> properNameMatches(String text) {
  final out = <NameHit>[];
  var i = 0;
  while (i < text.length) {
    ProperName? hit;
    for (final p in properNames) {
      if (p.text.length <= text.length - i && text.startsWith(p.text, i)) {
        hit = p; // properNames 已按長度排序 → 第一個命中即最長
        break;
      }
    }
    if (hit != null) {
      out.add((start: i, end: i + hit.text.length, type: hit.type));
      i += hit.text.length;
    } else {
      i++;
    }
  }
  return out;
}

/// [query] 在 [text] 中是否「只」以某個更長專名的一部分出現（沒有獨立出現）。
/// 例：搜「以利亞」而該節只有「以利亞撒」→ true（應濾掉，非本人）。
bool queryOnlyInsideLongerName(String text, String query) {
  final q = query.trim();
  if (q.isEmpty || !text.contains(q)) return false;
  final names = properNameMatches(text);
  var idx = text.indexOf(q);
  while (idx >= 0) {
    final insideLonger = names.any((m) =>
        m.start <= idx &&
        idx + q.length <= m.end &&
        (m.end - m.start) > q.length);
    if (!insideLonger) return false; // 有一次獨立出現（或就是該專名本身）
    idx = text.indexOf(q, idx + 1);
  }
  return true;
}

String entityTypeLabel(EntityType t) {
  switch (t) {
    case EntityType.person:
      return '人物';
    case EntityType.place:
      return '地點';
    case EntityType.event:
      return '事件';
  }
}
