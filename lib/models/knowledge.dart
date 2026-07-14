/// 聖經知識架構的資料模型（白板「七、交叉與知識架構」）。
///
/// ⛔ 所有「內容」（哪些經文平行、哪個預表對應哪個應驗、年代、人物生平、
/// 人物關係）都由使用者親寫；這裡只定義**格式與載入**。資料在
/// `assets/knowledge/knowledge.json`，預設全空，缺就顯示待補、不擋功能。
library;

/// 平行經文對照：一組講同一件事／相對應的經文（如四福音對觀）。
class ParallelPassage {
  final String title;
  final List<String> refs; // 節位字串，可跳轉

  const ParallelPassage({required this.title, required this.refs});

  factory ParallelPassage.fromJson(Map<String, dynamic> j) => ParallelPassage(
        title: j['title'] as String? ?? '',
        refs: ((j['refs'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      );
}

/// 舊約預表 → 新約應驗。
class TypeFulfillment {
  final String title;
  final String otRef; // 舊約預表經文
  final String ntRef; // 新約應驗經文
  final String note;

  const TypeFulfillment({
    required this.title,
    required this.otRef,
    required this.ntRef,
    required this.note,
  });

  factory TypeFulfillment.fromJson(Map<String, dynamic> j) => TypeFulfillment(
        title: j['title'] as String? ?? '',
        otRef: j['otRef'] as String? ?? '',
        ntRef: j['ntRef'] as String? ?? '',
        note: j['note'] as String? ?? '',
      );
}

/// 時間軸／事件線上的一個事件。
class TimelineEvent {
  final int order; // 排序用（小到大）
  final String era; // 分期，如「族長時期」
  final String title;
  final String when; // 年代「文字」（年代有爭議，不用數字），如「約主前 2000 年」
  final String ref; // 相關經文

  const TimelineEvent({
    required this.order,
    required this.era,
    required this.title,
    required this.when,
    required this.ref,
  });

  factory TimelineEvent.fromJson(Map<String, dynamic> j) => TimelineEvent(
        order: (j['order'] as num?)?.toInt() ?? 0,
        era: j['era'] as String? ?? '',
        title: j['title'] as String? ?? '',
        when: j['when'] as String? ?? '',
        ref: j['ref'] as String? ?? '',
      );
}

/// 人物生平中的一個重大事件。
class PersonEvent {
  final String title;
  final String ref;

  const PersonEvent({required this.title, required this.ref});

  factory PersonEvent.fromJson(Map<String, dynamic> j) => PersonEvent(
        title: j['title'] as String? ?? '',
        ref: j['ref'] as String? ?? '',
      );
}

/// 人物之間的一段關係（做成可點跳轉的關係鏈）。
class PersonRelation {
  final String type; // 關係，如「父」「子」「妻」「門徒」
  final String personId; // 對象人物 id（能跳過去）
  final String name; // 對象顯示名（personId 不存在時仍可顯示）

  const PersonRelation({
    required this.type,
    required this.personId,
    required this.name,
  });

  factory PersonRelation.fromJson(Map<String, dynamic> j) => PersonRelation(
        type: j['type'] as String? ?? '',
        personId: j['personId'] as String? ?? '',
        name: j['name'] as String? ?? '',
      );
}

/// 一位聖經人物：生平簡介＋重大事件＋關係。
class Person {
  final String id;
  final String name;
  final List<String> aka; // 別名
  final String bio; // 生平簡介
  final List<PersonEvent> events;
  final List<PersonRelation> relations;

  const Person({
    required this.id,
    required this.name,
    required this.aka,
    required this.bio,
    required this.events,
    required this.relations,
  });

  factory Person.fromJson(Map<String, dynamic> j) => Person(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? '',
        aka: ((j['aka'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        bio: j['bio'] as String? ?? '',
        events: ((j['events'] as List?) ?? const [])
            .map((e) => PersonEvent.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        relations: ((j['relations'] as List?) ?? const [])
            .map((e) =>
                PersonRelation.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );
}

/// 整份知識庫。
class KnowledgeBase {
  final List<ParallelPassage> parallels;
  final List<TypeFulfillment> types;
  final List<TimelineEvent> timeline;
  final List<Person> people;

  const KnowledgeBase({
    required this.parallels,
    required this.types,
    required this.timeline,
    required this.people,
  });

  static const empty = KnowledgeBase(
      parallels: [], types: [], timeline: [], people: []);

  factory KnowledgeBase.fromJson(Map<String, dynamic> j) {
    List<T> list<T>(String key, T Function(Map<String, dynamic>) f) =>
        ((j[key] as List?) ?? const [])
            .map((e) => f((e as Map).cast<String, dynamic>()))
            .toList();
    final tl = list('timeline', TimelineEvent.fromJson)
      ..sort((a, b) => a.order.compareTo(b.order));
    return KnowledgeBase(
      parallels: list('parallels', ParallelPassage.fromJson),
      types: list('types', TypeFulfillment.fromJson),
      timeline: tl,
      people: list('people', Person.fromJson),
    );
  }

  Person? personById(String id) {
    for (final p in people) {
      if (p.id == id) return p;
    }
    return null;
  }
}
