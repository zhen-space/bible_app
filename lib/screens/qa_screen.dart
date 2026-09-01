// 隱藏 Flutter 的 Visibility widget（此檔用本專案 Visibility enum，不用該 widget）。
import 'package:flutter/material.dart' hide Visibility;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/study_content.dart';
import '../providers/providers.dart';
import '../services/app_links.dart';
import '../services/qa_service.dart';
import '../services/verse_locator.dart';
import 'qa_voice_screen.dart';
import 'study_content_screen.dart';

/// 疑問 Q&A 首頁：已審核問題列表（精選置頂）＋分類過濾＋搜尋。
class QaScreen extends ConsumerStatefulWidget {
  const QaScreen({super.key});

  @override
  ConsumerState<QaScreen> createState() => _QaScreenState();
}

class _QaScreenState extends ConsumerState<QaScreen> {
  String _category = '';
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final ready = ref.watch(firebaseReadyProvider);
    final user = ref.watch(authUserProvider).value;
    final isAdmin = ref.watch(isAdminProvider);
    // 學生端只看已發布內容（approved≠published）
    final questionsAsync = ref.watch(publishedQuestionsProvider(_category));

    return Scaffold(
      appBar: AppBar(
        title: const Text('疑問 Q&A'),
        actions: [
          IconButton(
            icon: const Icon(Icons.mic_none),
            tooltip: '語音提問',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const QaVoiceScreen())),
          ),
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.fact_check_outlined),
              tooltip: '問題審核',
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const QaAdminScreen())),
            ),
          if (user != null)
            IconButton(
              icon: const Icon(Icons.person_outline),
              tooltip: '我的提問／追蹤／收藏',
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const MyQaScreen())),
            ),
        ],
      ),
      floatingActionButton: ready
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('提問'),
              onPressed: () => _ask(context, user != null),
            )
          : null,
      body: !ready
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('疑問 Q&A 需要連上雲端才能使用。', textAlign: TextAlign.center),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: '搜尋問題與回答…',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _query = v.trim()),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      _catChip('全部', ''),
                      for (final c in kQaCategories) _catChip(c, c),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: questionsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('載入失敗：$e')),
                    data: (all) {
                      final list = _filter(all);
                      if (list.isEmpty) {
                        return const Center(child: Text('目前沒有相符的問題'));
                      }
                      return ListView.separated(
                        itemCount: list.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, i) => _QuestionTile(question: list[i]),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  List<Question> _filter(List<Question> all) {
    if (_query.isEmpty) return all;
    final q = _query.toLowerCase();
    return all.where((question) {
      final hay = [
        question.title,
        question.body,
        question.answer?.content ?? '',
        ...?question.answer?.tags,
      ].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  Widget _catChip(String label, String value) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: _category == value,
          onSelected: (_) => setState(() => _category = value),
        ),
      );

  void _ask(BuildContext context, bool loggedIn) {
    if (!loggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('請先到「設定」用 Google 登入，才能提問')));
      return;
    }
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const AskQuestionScreen()));
  }
}

/// 列表中的一列問題。
class _QuestionTile extends StatelessWidget {
  final Question question;

  const _QuestionTile({required this.question});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: question.featured
          ? Icon(Icons.push_pin, color: scheme.secondary)
          : Icon(Icons.help_outline, color: scheme.primary),
      title: Text(question.title,
          maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Row(
        children: [
          _Pill(question.category),
          const SizedBox(width: 8),
          Text(question.isAnswered ? '已回答' : '待回答',
              style: TextStyle(
                  fontSize: 12,
                  color: question.isAnswered ? Colors.green : scheme.outline)),
        ],
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => QuestionDetailScreen(id: question.id)),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  const _Pill(this.text);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 11, color: scheme.onPrimaryContainer)),
    );
  }
}

/// 問題詳情：問題本體 + 回答（引用經文可跳轉、標籤）＋ 追蹤/收藏 ＋ 管理者操作。
class QuestionDetailScreen extends ConsumerStatefulWidget {
  final String id;
  const QuestionDetailScreen({super.key, required this.id});

  @override
  ConsumerState<QuestionDetailScreen> createState() =>
      _QuestionDetailScreenState();
}

class _QuestionDetailScreenState extends ConsumerState<QuestionDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final qAsync = ref.watch(questionProvider(widget.id));
    final user = ref.watch(authUserProvider).value;
    final isAdmin = ref.watch(isAdminProvider);
    final saved = ref.watch(savedQuestionIdsProvider).value ?? const {};
    final following = ref.watch(followingQuestionsProvider).value ?? const {};

    return Scaffold(
      appBar: AppBar(
        title: const Text('問題'),
        actions: [
          if (user != null)
            qAsync.maybeWhen(
              data: (q) => q == null
                  ? const SizedBox.shrink()
                  : IconButton(
                      icon: Icon(saved.contains(q.id)
                          ? Icons.bookmark
                          : Icons.bookmark_border),
                      tooltip: saved.contains(q.id) ? '取消收藏' : '收藏',
                      onPressed: () => _toggleSave(
                          user.uid, q.id, saved.contains(q.id)),
                    ),
              orElse: () => const SizedBox.shrink(),
            ),
        ],
      ),
      body: qAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('載入失敗：$e')),
        data: (q) {
          if (q == null) return const Center(child: Text('找不到這個問題'));
          // 進入詳情：把此問題標記為已讀（追蹤未讀提示用）
          if (user != null && following.containsKey(q.id)) {
            final seen = following[q.id] ?? 0;
            if (q.updatedAt > seen) {
              ref
                  .read(qaServiceProvider)
                  .markFollowSeen(user.uid, q.id, q.updatedAt)
                  .then((_) =>
                      ref.invalidate(followingQuestionsProvider));
            }
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(children: [
                _Pill(q.category),
                if (q.featured) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.push_pin, size: 16),
                ],
                const Spacer(),
                if (q.status != 'approved')
                  Text(q.status == 'pending' ? '待審核' : '已退回',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
              ]),
              const SizedBox(height: 10),
              Text(q.title,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              if (q.author.isNotEmpty)
                Text('提問：${q.author}',
                    style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              Text(q.body, style: const TextStyle(height: 1.7)),
              const SizedBox(height: 12),
              if (user != null)
                OutlinedButton.icon(
                  icon: Icon(following.containsKey(q.id)
                      ? Icons.notifications_active
                      : Icons.notifications_none),
                  label: Text(following.containsKey(q.id) ? '已追蹤（有新回答會提示）' : '追蹤這題'),
                  onPressed: () => _toggleFollow(
                      user.uid, q.id, following.containsKey(q.id)),
                ),
              const Divider(height: 32),
              _answerSection(context, q),
              if (isAdmin) ...[
                const Divider(height: 32),
                _adminControls(context, q),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _answerSection(BuildContext context, Question q) {
    final scheme = Theme.of(context).colorScheme;
    if (!q.isAnswered) {
      return Row(children: [
        Icon(Icons.hourglass_empty, size: 18, color: scheme.outline),
        const SizedBox(width: 8),
        const Text('尚未回答'),
      ]);
    }
    final a = q.answer!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.verified_outlined, size: 18, color: scheme.primary),
          const SizedBox(width: 6),
          Text('回答',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: scheme.primary)),
        ]),
        const SizedBox(height: 8),
        Text(a.content, style: const TextStyle(height: 1.8)),
        ..._sourcesView(context, a),
        if (a.tags.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            children: [for (final t in a.tags) _Pill('#$t')],
          ),
        ],
        if (q.answerVersions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('回答更新紀錄（${q.answerVersions.length}）',
                  style: Theme.of(context).textTheme.bodySmall),
              children: [
                for (final v in q.answerVersions.reversed)
                  ListTile(
                    dense: true,
                    title: Text(v.content,
                        style: const TextStyle(height: 1.5)),
                    subtitle: Text(_ymd(v.updatedAt)),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _adminControls(BuildContext context, Question q) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('管理者操作',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              icon: const Icon(Icons.edit_note),
              label: Text(q.isAnswered ? '編輯回答' : '回答'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => QaAnswerEditor(question: q)),
              ).then((_) => ref.invalidate(questionProvider(q.id))),
            ),
            if (q.status != 'approved')
              OutlinedButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('核准'),
                onPressed: () => _admin(() =>
                    ref.read(qaServiceProvider).approveQuestion(q.id), q.id),
              ),
            // 發布是獨立動作：唯有已回答才可發布；發布後學生端才取得得到。
            if (q.isAnswered)
              FilledButton.icon(
                style: q.published
                    ? FilledButton.styleFrom(
                        backgroundColor:
                            Theme.of(context).colorScheme.secondary)
                    : null,
                icon: Icon(q.published
                    ? Icons.public_off
                    : Icons.publish_outlined),
                label: Text(q.published ? '取消發布' : '發布給學生端'),
                onPressed: () => q.published
                    ? _admin(
                        () => ref
                            .read(qaServiceProvider)
                            .setPublished(q.id, false),
                        q.id)
                    : _publishWithSourceValidation(q),
              ),
            if (q.status != 'rejected')
              OutlinedButton.icon(
                icon: const Icon(Icons.block),
                label: const Text('退回'),
                onPressed: () => _admin(() =>
                    ref.read(qaServiceProvider).rejectQuestion(q.id), q.id),
              ),
            OutlinedButton.icon(
              icon: Icon(q.featured ? Icons.star : Icons.star_border),
              label: Text(q.featured ? '取消精選' : '設為精選'),
              onPressed: () => _admin(
                  () => ref
                      .read(qaServiceProvider)
                      .setFeatured(q.id, !q.featured),
                  q.id),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _admin(Future<void> Function() op, String id) async {
    final m = ScaffoldMessenger.of(context);
    try {
      await op();
      ref.invalidate(questionProvider(id));
      ref.invalidate(pendingQuestionsProvider);
      ref.invalidate(publishedQuestionsProvider);
      ref.invalidate(awaitingPublishQuestionsProvider);
      m.showSnackBar(const SnackBar(content: Text('已更新')));
    } catch (e) {
      m.showSnackBar(SnackBar(content: Text('操作失敗：$e')));
    }
  }

  /// 發布前**重新驗證**回答依據：任何 study content source 若已非 published
  /// （在草稿建立後失效：被退回/封存/改草稿），阻止發布——不得只依賴 picker 當下狀態。
  Future<void> _publishWithSourceValidation(Question q) async {
    final m = ScaffoldMessenger.of(context);
    final repo = ref.read(studyContentRepositoryProvider);
    final sources =
        (q.answer?.sources ?? const <AnswerSource>[]).where((s) => s.kind == 'study_content');
    final invalid = <String>[];
    for (final s in sources) {
      if (!await repo.isPublishedNow(s.contentId)) {
        invalid.add(s.evidence.isEmpty ? s.contentId : s.evidence);
      }
    }
    if (!mounted) return;
    if (invalid.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('無法發布：回答依據已失效'),
          content: Text(
              '以下「已發布內容」依據目前已不是 Published 狀態，請先在回答編輯器移除或更換後再發布：\n\n'
              '${invalid.join("\n")}'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('知道了')),
          ],
        ),
      );
      m.showSnackBar(const SnackBar(content: Text('發布已中止：回答依據需為已發布內容')));
      return;
    }
    await _admin(() => ref.read(qaServiceProvider).setPublished(q.id, true), q.id);
  }

  Future<void> _toggleSave(String uid, String id, bool saved) async {
    final svc = ref.read(qaServiceProvider);
    saved ? await svc.unsaveQuestion(uid, id) : await svc.saveQuestion(uid, id);
    ref.invalidate(savedQuestionIdsProvider);
  }

  Future<void> _toggleFollow(String uid, String id, bool following) async {
    final svc = ref.read(qaServiceProvider);
    following
        ? await svc.unfollowQuestion(uid, id)
        : await svc.followQuestion(uid, id);
    ref.invalidate(followingQuestionsProvider);
  }

  void _jump(BuildContext context, String ref_) =>
      AppLinks.openVerseRef(context, ref, ref_);

  /// 學生端「回答依據」呈現：經文（可點→臨時 Reader）＋已發布內容
  /// （student 可點開詳情；internal 只顯示 title＋「已審核內容·內部參考」，不可點）。
  /// **internal source 的 title 取自 answer.sources 的公開快照 evidence，
  /// 學生端不需要（也不會）去讀 internal study_content 文件。**
  List<Widget> _sourcesView(BuildContext context, QaAnswer a) {
    final scriptureSources =
        a.sources.where((s) => s.kind == 'scripture').toList();
    final studySources =
        a.sources.where((s) => s.kind == 'study_content').toList();
    // 經文依據＝結構化 scripture sources 優先；沒有才退回 legacy scriptures（相容）。
    final scriptureRefs = scriptureSources.isNotEmpty
        ? scriptureSources.map((s) => s.ref.isNotEmpty ? s.ref : s.contentId).toList()
        : a.scriptures;
    if (scriptureRefs.isEmpty && studySources.isEmpty) return const [];
    return [
      const SizedBox(height: 12),
      Text('回答依據', style: Theme.of(context).textTheme.labelLarge),
      if (scriptureRefs.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text('經文', style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final r in scriptureRefs)
            ActionChip(
              avatar: const Icon(Icons.menu_book, size: 16),
              label: Text(r),
              onPressed: () => _jump(context, r),
            ),
        ]),
      ],
      if (studySources.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('已發布內容', style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        for (final s in studySources) _studySourceTile(context, s),
      ],
    ];
  }

  Widget _studySourceTile(BuildContext context, AnswerSource s) {
    final title = s.evidence.isNotEmpty ? s.evidence : s.contentId;
    if (s.isStudentOpenable) {
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 3),
        child: ListTile(
          dense: true,
          leading: const Icon(Icons.article_outlined),
          title: Text(title),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openStudyContent(context, s.contentId),
        ),
      );
    }
    // internal：顯示 title（來自公開快照）＋標示，不可點；不讀 internal 文件。
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        dense: true,
        enabled: false,
        leading: const Icon(Icons.lock_outline),
        title: Text(title),
        subtitle: const Text('已審核內容 · 內部參考'),
      ),
    );
  }

  Future<void> _openStudyContent(BuildContext context, String contentId) async {
    final m = ScaffoldMessenger.of(context);
    final item = await ref
        .read(studyContentRepositoryProvider)
        .fetchStudentStudyContentById(contentId);
    if (!context.mounted) return;
    if (item == null) {
      m.showSnackBar(const SnackBar(content: Text('此內容目前無法瀏覽。')));
      return;
    }
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => StudentStudyContentDetail(item: item)));
  }
}

/// 提問表單。
class AskQuestionScreen extends ConsumerStatefulWidget {
  const AskQuestionScreen({super.key});

  @override
  ConsumerState<AskQuestionScreen> createState() => _AskQuestionScreenState();
}

class _AskQuestionScreenState extends ConsumerState<AskQuestionScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  String _category = kQaCategories.first;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('提問')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: '問題標題',
              hintText: '一句話講清楚你想問什麼',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _body,
            maxLines: 6,
            minLines: 3,
            decoration: const InputDecoration(
              labelText: '詳細說明',
              hintText: '把來龍去脈、你的困惑寫清楚',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          Text('分類', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              for (final c in kQaCategories)
                ChoiceChip(
                  label: Text(c),
                  selected: _category == c,
                  onSelected: (_) => setState(() => _category = c),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text('提交後由管理者審核，通過才會公開。',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send),
            label: Text(_saving ? '提交中…' : '提交問題'),
            onPressed: _saving ? null : _submit,
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final user = ref.read(authUserProvider).value;
    if (user == null) return;
    final title = _title.text.trim();
    final body = _body.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('請先寫問題標題')));
      return;
    }
    setState(() => _saving = true);
    final m = ScaffoldMessenger.of(context);
    try {
      await ref.read(qaServiceProvider).submitQuestion(
            uid: user.uid,
            authorName: user.displayName ?? '',
            title: title,
            body: body,
            category: _category,
          );
      ref.invalidate(myQuestionsProvider);
      m.showSnackBar(const SnackBar(content: Text('已提交，待審核通過後公開')));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      m.showSnackBar(SnackBar(content: Text('提交失敗：$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

/// 管理者回答編輯（引用經文、標籤；更新時保留舊版本）。
class QaAnswerEditor extends ConsumerStatefulWidget {
  final Question question;
  const QaAnswerEditor({super.key, required this.question});

  @override
  ConsumerState<QaAnswerEditor> createState() => _QaAnswerEditorState();
}

class _QaAnswerEditorState extends ConsumerState<QaAnswerEditor> {
  late final TextEditingController _content;
  late final TextEditingController _tags;
  // 回答依據：結構化經文 sources（kind='scripture'）＋已發布內容 sources（kind='study_content'）。
  late List<AnswerSource> _scriptureSources;
  late List<AnswerSource> _studySources;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final a = widget.question.answer;
    _content = TextEditingController(text: a?.content ?? '');
    _tags = TextEditingController(text: (a?.tags ?? []).join(' '));
    final all = [...(a?.sources ?? const <AnswerSource>[])];
    _studySources = all.where((s) => s.kind == 'study_content').toList();
    _scriptureSources = all.where((s) => s.kind == 'scripture').toList();
    // 相容：舊回答只有 legacy scriptures → 種入結構化經文 sources 供編輯。
    if (_scriptureSources.isEmpty && (a?.scriptures.isNotEmpty ?? false)) {
      _scriptureSources = [
        for (final r in a!.scriptures)
          AnswerSource(contentId: r, version: 0, kind: 'scripture', ref: r, evidence: r)
      ];
    }
  }

  @override
  void dispose() {
    _content.dispose();
    _tags.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('回答')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(widget.question.title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(
            controller: _content,
            maxLines: 10,
            minLines: 5,
            decoration: const InputDecoration(
              labelText: '回答內容',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tags,
            decoration: const InputDecoration(
              labelText: '標籤（空格分隔，例：救恩 恩典）',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 20),
          _sourcesSection(),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cloud_upload),
            label: Text(_saving ? '儲存中…' : '儲存回答並公開'),
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }

  /// 「回答依據」編輯：經文（結構化 scripture sources）＋已發布內容（study content sources）。
  Widget _sourcesSection() {
    final scheme = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.menu_book, size: 18, color: scheme.primary),
        const SizedBox(width: 6),
        const Text('回答依據 · 經文',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const Spacer(),
        TextButton.icon(
          icon: const Icon(Icons.add, size: 16),
          label: const Text('新增經文依據'),
          onPressed: _addScriptureSource,
        ),
      ]),
      if (_scriptureSources.isEmpty)
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('尚未加入經文依據。'))
      else
        for (int i = 0; i < _scriptureSources.length; i++)
          _reorderTile(_scriptureSources, i, Icons.menu_book,
              _scriptureSources[i].ref, ''),
      const SizedBox(height: 16),
      Row(children: [
        Icon(Icons.link, size: 18, color: scheme.primary),
        const SizedBox(width: 6),
        const Text('回答依據 · 已發布內容',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const Spacer(),
        TextButton.icon(
          icon: const Icon(Icons.add, size: 16),
          label: const Text('新增已發布內容'),
          onPressed: _pickSource,
        ),
      ]),
      Text('順序＝學生端「回答依據」顯示順序。內部內容會標示，學生端不可點開。',
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 6),
      if (_studySources.isEmpty)
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('尚未加入已發布內容依據。'))
      else
        for (int i = 0; i < _studySources.length; i++)
          _reorderTile(
              _studySources,
              i,
              Icons.article_outlined,
              _studySources[i].evidence.isEmpty
                  ? _studySources[i].contentId
                  : _studySources[i].evidence,
              '${_studySources[i].contentId} · v${_studySources[i].version} · ${_studySources[i].access == 'student' ? '學生可見' : '內部'}'),
    ]);
  }

  Widget _reorderTile(
      List<AnswerSource> list, int i, IconData icon, String title, String sub) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        dense: true,
        leading: Icon(icon),
        title: Text(title.isEmpty ? '(未命名)' : title),
        subtitle: sub.isEmpty ? null : Text(sub),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            icon: const Icon(Icons.arrow_upward, size: 18),
            onPressed: i == 0
                ? null
                : () => setState(() {
                      final x = list.removeAt(i);
                      list.insert(i - 1, x);
                    }),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_downward, size: 18),
            onPressed: i == list.length - 1
                ? null
                : () => setState(() {
                      final x = list.removeAt(i);
                      list.insert(i + 1, x);
                    }),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => list.removeAt(i)),
          ),
        ]),
      ),
    );
  }

  /// 結構化經文依據：以 VerseLocator 解析節位（正式 reference authority），可帶結束節。
  Future<void> _addScriptureSource() async {
    final refC = TextEditingController();
    final endC = TextEditingController();
    final added = await showDialog<AnswerSource>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('新增經文依據'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: refC,
            autofocus: true,
            decoration: const InputDecoration(
                labelText: '起始節位（例：約3:16）', isDense: true),
          ),
          TextField(
            controller: endC,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: '結束節（選填，同章，例：18）', isDense: true),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final books = ref.read(booksProvider).value ?? const [];
              final parsed = VerseLocator.parse(refC.text.trim(), books);
              if (parsed == null || parsed.verse == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('無法解析節位（例：約3:16）')));
                return;
              }
              final end = int.tryParse(endC.text.trim());
              final refStr = end != null && end > parsed.verse!
                  ? '${refC.text.trim()}-$end'
                  : refC.text.trim();
              Navigator.pop(
                  context,
                  AnswerSource(
                      contentId: refStr,
                      version: 0,
                      kind: 'scripture',
                      ref: refStr,
                      evidence: refStr));
            },
            child: const Text('加入'),
          ),
        ],
      ),
    );
    if (added != null) setState(() => _scriptureSources.add(added));
  }

  /// 只列 **status==published** 的 study content（Draft/Review/Rejected/Archived 不得成為
  /// source）；含 internal，UI 標示 visibility 讓管理員清楚。
  Future<void> _pickSource() async {
    final items = await ref.read(adminPublishedSourcesProvider.future);
    if (!mounted) return;
    final chosen = await showModalBottomSheet<StudyContentItem>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, controller) => items.isEmpty
            ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('目前沒有已發布的研讀內容可引用。')))
            : ListView(
                controller: controller,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('選擇已發布內容作依據',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  for (final it in items)
                    ListTile(
                      title: Text(it.title.isEmpty ? it.id : it.title),
                      subtitle: Row(children: [
                        Text('${it.contentType?.label ?? ''} · '),
                        Text(
                          it.visibility == Visibility.student
                              ? 'Published · Student'
                              : 'Published · Internal',
                          style: TextStyle(
                            color: it.visibility == Visibility.student
                                ? Colors.green.shade700
                                : Colors.blueGrey,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ]),
                      onTap: () => Navigator.pop(context, it),
                    ),
                ],
              ),
      ),
    );
    if (chosen == null) return;
    setState(() {
      if (_studySources.any((s) => s.contentId == chosen.id)) return;
      _studySources.add(AnswerSource(
        contentId: chosen.id,
        version: chosen.version,
        kind: 'study_content',
        evidence: chosen.title, // 公開快照 label：學生端不必讀 internal 文件即可顯示
        access: chosen.visibility == Visibility.student ? 'student' : 'internal',
      ));
    });
  }

  Future<void> _save() async {
    final content = _content.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('請先寫回答內容')));
      return;
    }
    setState(() => _saving = true);
    final m = ScaffoldMessenger.of(context);
    try {
      final tags = _tags.text
          .split(RegExp(r'[\s,，#＃]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      // 結構化 scripture sources 為 authority；同時鏡射節位字串到 legacy
      // `scriptures`（向後相容：舊讀者／舊渲染仍可顯示）。
      final scriptures =
          _scriptureSources.map((s) => s.ref).where((r) => r.isNotEmpty).toList();
      final sources = [..._scriptureSources, ..._studySources];
      await ref.read(qaServiceProvider).saveAnswer(
            question: widget.question,
            content: content,
            scriptures: scriptures,
            tags: tags,
            sources: sources,
          );
      ref.invalidate(questionProvider(widget.question.id));
      ref.invalidate(publishedQuestionsProvider);
      ref.invalidate(awaitingPublishQuestionsProvider);
      ref.invalidate(pendingQuestionsProvider);
      m.showSnackBar(const SnackBar(
          content: Text('已儲存回答（尚未發布，請於管理區按「發布」才會對學生端顯示）')));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      m.showSnackBar(SnackBar(content: Text('儲存失敗：$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

/// 管理者：待審問題佇列。
class QaAdminScreen extends ConsumerWidget {
  const QaAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(pendingQuestionsProvider);
    final awaitingAsync = ref.watch(awaitingPublishQuestionsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('問題審核・發布')),
      body: ListView(
        children: [
          _AdminSectionHeader(
              '已回答・待發布（發布後學生端才看得到）',
              Theme.of(context).colorScheme.primary),
          awaitingAsync.when(
            loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Padding(
                padding: const EdgeInsets.all(16), child: Text('載入失敗：$e')),
            data: (items) => items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('沒有待發布的已回答問題'))
                : Column(
                    children: [
                      for (final q in items)
                        ListTile(
                          leading: const Icon(Icons.publish_outlined),
                          title: Text(q.title),
                          subtitle: Text('${q.category}　${q.author}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    QuestionDetailScreen(id: q.id)),
                          ),
                        ),
                    ],
                  ),
          ),
          const Divider(height: 1),
          _AdminSectionHeader('待審提問', Colors.grey),
          pendingAsync.when(
            loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Padding(
                padding: const EdgeInsets.all(16), child: Text('載入失敗：$e')),
            data: (items) => items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('目前沒有待審問題'))
                : Column(
                    children: [
                      for (final q in items)
                        ListTile(
                          leading: const Icon(Icons.help_outline),
                          title: Text(q.title),
                          subtitle: Text('${q.category}　${q.author}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    QuestionDetailScreen(id: q.id)),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _AdminSectionHeader extends StatelessWidget {
  final String text;
  final Color color;

  const _AdminSectionHeader(this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(color: color, fontWeight: FontWeight.bold)),
    );
  }
}

/// 我的提問 / 我追蹤 / 我收藏。
class MyQaScreen extends ConsumerWidget {
  const MyQaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('我的 Q&A'),
          bottom: const TabBar(
            tabs: [Tab(text: '我的提問'), Tab(text: '追蹤'), Tab(text: '收藏')],
          ),
        ),
        body: const TabBarView(
          children: [_MyQuestionsTab(), _FollowingTab(), _SavedTab()],
        ),
      ),
    );
  }
}

class _MyQuestionsTab extends ConsumerWidget {
  const _MyQuestionsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(myQuestionsProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('載入失敗：$e')),
      data: (list) {
        if (list.isEmpty) return const Center(child: Text('你還沒有提問'));
        return ListView(
          children: [
            for (final q in list)
              ListTile(
                title: Text(q.title),
                subtitle: Text(_statusLabel(q)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => QuestionDetailScreen(id: q.id)),
                ),
              ),
          ],
        );
      },
    );
  }

  String _statusLabel(Question q) {
    final s = switch (q.status) {
      'approved' => '已公開',
      'rejected' => '已退回',
      _ => '審核中',
    };
    return '$s　${q.isAnswered ? '已回答' : '待回答'}';
  }
}

class _FollowingTab extends ConsumerWidget {
  const _FollowingTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final following = ref.watch(followingQuestionsProvider);
    return following.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('載入失敗：$e')),
      data: (map) {
        if (map.isEmpty) return const Center(child: Text('你還沒有追蹤任何問題'));
        final ids = map.keys.toList();
        return ListView.builder(
          itemCount: ids.length,
          itemBuilder: (_, i) {
            final id = ids[i];
            final seen = map[id] ?? 0;
            final qAsync = ref.watch(questionProvider(id));
            return qAsync.maybeWhen(
              data: (q) {
                if (q == null) return const SizedBox.shrink();
                final unread = q.isAnswered && q.updatedAt > seen;
                return ListTile(
                  leading: Icon(
                      unread ? Icons.mark_email_unread : Icons.notifications,
                      color: unread
                          ? Theme.of(context).colorScheme.error
                          : null),
                  title: Text(q.title),
                  subtitle: Text(unread
                      ? '有新回答！'
                      : (q.isAnswered ? '已回答' : '待回答')),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => QuestionDetailScreen(id: id)),
                  ),
                );
              },
              orElse: () => const ListTile(title: Text('載入中…')),
            );
          },
        );
      },
    );
  }
}

class _SavedTab extends ConsumerWidget {
  const _SavedTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(savedQuestionIdsProvider);
    return saved.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('載入失敗：$e')),
      data: (ids) {
        if (ids.isEmpty) return const Center(child: Text('你還沒有收藏任何問題'));
        final list = ids.toList();
        return ListView.builder(
          itemCount: list.length,
          itemBuilder: (_, i) {
            final qAsync = ref.watch(questionProvider(list[i]));
            return qAsync.maybeWhen(
              data: (q) => q == null
                  ? const SizedBox.shrink()
                  : ListTile(
                      leading: const Icon(Icons.bookmark),
                      title: Text(q.title),
                      subtitle: Text(q.isAnswered ? '已回答' : '待回答'),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => QuestionDetailScreen(id: q.id)),
                      ),
                    ),
              orElse: () => const ListTile(title: Text('載入中…')),
            );
          },
        );
      },
    );
  }
}

String _ymd(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.year}/${d.month.toString().padLeft(2, '0')}/'
      '${d.day.toString().padLeft(2, '0')}';
}
