import '../models/models.dart';

/// A ranked Bible search result. Exact wording always ranks ahead of related
/// wording, while [matchedTerms] explains which local concepts caused a match.
class VerseSearchHit {
  const VerseSearchHit({
    required this.verse,
    required this.score,
    required this.isExact,
    required this.matchedTerms,
  });

  final VerseRef verse;
  final double score;
  final bool isExact;
  final List<String> matchedTerms;
}

/// Local, deterministic related-verse search for Traditional Chinese.
///
/// This intentionally does not send the query to an external service. It
/// combines exact phrase matching, meaningful words from a natural-language
/// sentence, and a small transparent Bible-language concept map.
class RelatedVerseSearch {
  const RelatedVerseSearch._();

  static List<VerseSearchHit> search(
    List<Book> books,
    String query, {
    int limit = 100,
  }) {
    final normalizedQuery = normalize(query);
    if (normalizedQuery.isEmpty || limit <= 0) return const [];

    final directTerms = _directTerms(query, normalizedQuery);
    final relatedTerms = _relatedTerms(normalizedQuery);
    final hits = <VerseSearchHit>[];

    for (final book in books) {
      for (
        var chapterIndex = 0;
        chapterIndex < book.chapters.length;
        chapterIndex++
      ) {
        final chapter = book.chapters[chapterIndex];
        for (var verseIndex = 0; verseIndex < chapter.length; verseIndex++) {
          final raw = chapter[verseIndex];
          final text = normalize(raw);
          final exact = text.contains(normalizedQuery);
          var score = exact ? 10000.0 + normalizedQuery.length * 20 : 0.0;
          final matched = <String>[];

          for (final term in directTerms) {
            if (!text.contains(term)) continue;
            score += 180 + term.length * 24;
            matched.add(term);
          }
          for (final entry in relatedTerms.entries) {
            final term = entry.key;
            if (!text.contains(term)) continue;
            score += entry.value + term.length * 8;
            matched.add(term);
          }

          // A related result must have a meaningful overlap. This prevents a
          // long conversational query from producing arbitrary subsequences.
          if (!exact && matched.isEmpty) continue;
          hits.add(
            VerseSearchHit(
              verse: VerseRef(
                bookId: book.id,
                chapter: chapterIndex + 1,
                verse: verseIndex + 1,
                text: raw,
              ),
              score: score,
              isExact: exact,
              matchedTerms: matched.toSet().toList(growable: false),
            ),
          );
        }
      }
    }

    hits.sort((a, b) {
      final byExact = (b.isExact ? 1 : 0).compareTo(a.isExact ? 1 : 0);
      if (byExact != 0) return byExact;
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final byBook = a.verse.bookId.compareTo(b.verse.bookId);
      if (byBook != 0) return byBook;
      final byChapter = a.verse.chapter.compareTo(b.verse.chapter);
      if (byChapter != 0) return byChapter;
      return a.verse.verse.compareTo(b.verse.verse);
    });
    return hits.take(limit).toList(growable: false);
  }

  static String normalize(String value) => value.toLowerCase().replaceAll(
    RegExp(r'[\s，、。；：！？「」『』（）,.；;:!?()　]'),
    '',
  );

  static Set<String> _directTerms(String rawQuery, String normalizedQuery) {
    final terms = <String>{};
    final chunks = rawQuery
        .split(RegExp(r'[\s，、。；：！？「」『』（）,.；;:!?()　]+'))
        .map(normalize)
        .where((term) => term.length >= 2);
    terms.addAll(chunks);

    var reduced = normalizedQuery;
    for (final filler in _conversationFillers) {
      reduced = reduced.replaceAll(filler, '|');
    }
    terms.addAll(
      reduced.split('|').where((term) => term.length >= 2 && term.length <= 12),
    );

    // Short queries are usually deliberate Bible phrases. Long conversational
    // sentences are not added whole because they would never occur verbatim.
    if (normalizedQuery.length <= 12) terms.add(normalizedQuery);
    return terms;
  }

  static Map<String, double> _relatedTerms(String normalizedQuery) {
    final terms = <String, double>{};
    for (final concept in _concepts.entries) {
      if (concept.key.any(normalizedQuery.contains)) {
        for (var i = 0; i < concept.value.length; i++) {
          final term = concept.value[i];
          // Earlier terms are close synonyms; later ones are broader themes.
          final weight = 180.0 - i * 16;
          if ((terms[term] ?? 0) < weight) terms[term] = weight;
        }
      }
    }
    return terms;
  }

  static const _conversationFillers = <String>[
    '我覺得',
    '我很',
    '我想',
    '我該',
    '我要',
    '有沒有',
    '可以',
    '應該',
    '怎麼辦',
    '不知道',
    '的時候',
    '時候',
    '關於',
    '請問',
  ];

  static const Map<List<String>, List<String>> _concepts = {
    ['焦慮', '擔心', '憂心', '緊張', '壓力', '煩惱']: [
      '掛慮',
      '憂慮',
      '心懷意念',
      '平安',
      '重擔',
      '安息',
      '倚靠',
    ],
    ['害怕', '恐懼', '恐慌', '膽怯', '不安']: ['懼怕', '膽怯', '平安', '同在', '壯膽'],
    ['勇氣', '需要勇氣', '沒有勇氣', '膽量']: ['剛強', '壯膽', '力量', '懼怕', '膽怯'],
    ['傷心', '難過', '低落', '沮喪', '痛苦', '哭泣']: ['憂傷', '痛苦', '安慰', '喜樂', '眼淚'],
    ['孤單', '孤獨', '沒有人陪', '被遺棄']: ['同在', '離棄', '撇下', '安慰'],
    ['生氣', '憤怒', '發脾氣', '氣人']: ['怒氣', '發怒', '忿怒', '饒恕', '和睦'],
    ['原諒', '寬恕', '得罪']: ['饒恕', '赦免', '認罪'],
    ['迷惘', '迷茫', '不知道怎麼辦', '沒有方向', '做決定']: ['智慧', '引導', '道路', '指教', '腳步'],
    ['工作', '疲累', '疲倦', '累了', '忙碌']: ['勞苦', '重擔', '安息', '殷勤'],
    ['失眠', '睡不著', '睡不好', '難以入睡']: ['躺下睡覺', '安然睡覺', '安睡', '睡臥', '安歇', '平安'],
    ['生病', '疾病', '受傷', '健康']: ['醫治', '軟弱', '病', '康健'],
    ['喪親', '失去親人', '面對死亡', '死亡', '哀傷']: ['復活', '永生', '安慰', '眼淚', '死亡'],
    ['禱告', '向神說', '求神']: ['祈求', '呼求', '感謝', '禱告'],
    ['信心', '相信神', '依靠神']: ['信靠', '倚靠', '信心'],
    ['愛人', '相處', '人際關係', '朋友']: ['彼此相愛', '愛人如己', '鄰舍', '和睦'],
    ['婚姻', '夫妻', '配偶', '另一半']: ['丈夫', '妻子', '一體', '彼此相愛'],
    ['家庭', '家人', '親子', '孩子', '教養']: ['兒女', '父母', '家', '教養'],
    ['金錢', '缺錢', '貧窮', '需要']: ['供應', '缺乏', '財寶', '富足'],
    ['誘惑', '試探', '犯罪']: ['試探', '罪', '逃避', '忍受'],
    ['感謝', '感恩']: ['感謝', '稱謝', '恩典'],
    ['希望', '絕望', '沒有盼望']: ['盼望', '指望', '忍耐'],
  };
}
