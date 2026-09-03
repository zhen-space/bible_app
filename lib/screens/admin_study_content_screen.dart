// 隱藏 Flutter 的 Visibility widget，避免與本專案的 Visibility enum 名稱衝突（此檔不用該 widget）。
import 'package:flutter/material.dart' hide Visibility;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/study_content.dart';
import '../providers/providers.dart';
import '../services/study_content_repository.dart';

// ============================ 共用 badge ============================
// Status 與 Student visibility **永遠分開顯示**（Published≠Student-visible）。

Widget statusBadge(BuildContext c, ContentStatus s) {
  final scheme = Theme.of(c).colorScheme;
  final color = switch (s) {
    ContentStatus.draft => Colors.grey,
    ContentStatus.review => Colors.orange,
    ContentStatus.published => scheme.primary,
    ContentStatus.rejected => scheme.error,
    ContentStatus.archived => Colors.blueGrey,
  };
  return _pill(s.label, color);
}

/// visibility badge。null（缺失）以「學生不可瀏覽」呈現（fail-closed 顯示，不誤導）。
Widget visibilityBadge(BuildContext c, Visibility? v) {
  final student = v == Visibility.student;
  return _pill(
    student ? '學生可瀏覽' : '學生不可瀏覽',
    student ? Colors.green.shade700 : Colors.blueGrey,
    technical: v?.name ?? 'internal',
  );
}

Widget _pill(String text, Color color, {String? technical}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(text,
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: FontWeight.w600)),
        if (technical != null) ...[
          const SizedBox(width: 4),
          Text('· $technical',
              style:
                  TextStyle(fontSize: 10, color: color.withValues(alpha: 0.8))),
        ],
      ]),
    );

/// Published + 某 visibility 的完整人話（送審/發佈確認共用）。
String visibilityMeaning(Visibility? v) => v == Visibility.student
    ? '已發布 / 學生可瀏覽'
    : '已發布 / 學生不可瀏覽';

// ============================ Study Content 清單 ============================

class AdminStudyContentScreen extends ConsumerStatefulWidget {
  const AdminStudyContentScreen({super.key});

  @override
  ConsumerState<AdminStudyContentScreen> createState() =>
      _AdminStudyContentScreenState();
}

class _AdminStudyContentScreenState
    extends ConsumerState<AdminStudyContentScreen> {
  ContentStatus? _status;
  Visibility? _visibility;
  bool _visibilityFilterOn = false;
  StudyContentType? _type;
  String? _provenance; // 'native' | 'migrated_legacy'
  String _query = '';

  bool _match(StudyContentItem it) {
    if (_status != null && it.status != _status) return false;
    if (_visibilityFilterOn && it.visibility != _visibility) return false;
    if (_type != null && it.contentType != _type) return false;
    if (_provenance != null) {
      final src = it.provenance.source;
      final isMigrated = src == StudyContentSource.migratedLegacy.wire;
      if (_provenance == 'migrated_legacy' && !isMigrated) return false;
      if (_provenance == 'native' && isMigrated) return false;
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      if (!it.title.toLowerCase().contains(q) &&
          !it.tags.any((t) => t.toLowerCase().contains(q)) &&
          !it.topicIds.any((t) => t.toLowerCase().contains(q)) &&
          !it.scriptureRefs.any((r) => r.toLowerCase().contains(q))) {
        return false;
      }
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final rowsAsync = ref.watch(adminStudyContentListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('研讀內容')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('新增研讀內容'),
        onPressed: _createNew,
      ),
      body: Column(
        children: [
          _filters(),
          const Divider(height: 1),
          Expanded(
            child: rowsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('載入失敗：$e')),
              data: (rows) {
                final filtered =
                    rows.where((r) => _match(r.editorial)).toList();
                if (filtered.isEmpty) {
                  return const Center(
                      child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text('沒有符合條件的研讀內容。右下角可新增。')));
                }
                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => _row(filtered[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filters() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Column(children: [
          TextField(
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search),
              hintText: '搜尋標題／標籤／主題／經文',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _dropdown<ContentStatus?>(
                '狀態',
                _status,
                [null, ...ContentStatus.values],
                (s) => s?.label ?? '全部狀態',
                (s) => setState(() => _status = s),
              ),
              const SizedBox(width: 8),
              _dropdown<String>(
                '學生瀏覽',
                _visibilityFilterOn
                    ? (_visibility == Visibility.student ? 'student' : 'internal')
                    : 'all',
                const ['all', 'student', 'internal'],
                (s) => {
                  'all': '全部瀏覽權',
                  'student': '學生可瀏覽',
                  'internal': '學生不可瀏覽'
                }[s]!,
                (s) => setState(() {
                  _visibilityFilterOn = s != 'all';
                  _visibility =
                      s == 'student' ? Visibility.student : Visibility.internal;
                }),
              ),
              const SizedBox(width: 8),
              _dropdown<StudyContentType?>(
                '型別',
                _type,
                [null, ...StudyContentType.values],
                (t) => t?.label ?? '全部型別',
                (t) => setState(() => _type = t),
              ),
              const SizedBox(width: 8),
              _dropdown<String?>(
                '來源',
                _provenance,
                const [null, 'native', 'migrated_legacy'],
                (s) => {
                  null: '全部來源',
                  'native': 'Native / 後台建立',
                  'migrated_legacy': 'Legacy 遷移'
                }[s]!,
                (s) => setState(() => _provenance = s),
              ),
            ]),
          ),
        ]),
      );

  Widget _dropdown<T>(String hint, T value, List<T> items,
          String Function(T) label, ValueChanged<T> onChanged) =>
      DropdownButton<T>(
        value: value,
        hint: Text(hint),
        underline: const SizedBox.shrink(),
        items: [
          for (final it in items)
            DropdownMenuItem(value: it, child: Text(label(it)))
        ],
        onChanged: (v) => onChanged(v as T),
      );

  Widget _row(AdminStudyRow r) {
    final it = r.editorial;
    final migrated =
        it.provenance.source == StudyContentSource.migratedLegacy.wire;
    return ListTile(
      title: Text(it.title.isEmpty ? '(未命名)' : it.title,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(spacing: 6, runSpacing: 4, children: [
          _pill(it.contentType?.label ?? '未知型別', Colors.indigo),
          statusBadge(context, it.status),
          visibilityBadge(context, it.visibility),
          if (migrated) _pill('Legacy 遷移', Colors.brown),
          if (it.topicIds.isNotEmpty) _pill('主題 ${it.topicIds.length}', Colors.teal),
          _pill('v${it.version}', Colors.grey),
        ]),
      ),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _open(r),
    );
  }

  Future<void> _createNew() async {
    final type = await showDialog<StudyContentType>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('選擇內容型別'),
        children: [
          for (final t in StudyContentType.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, t),
              child: ListTile(
                  leading: const Icon(Icons.article_outlined),
                  title: Text(t.label),
                  subtitle: Text(t.wire)),
            ),
        ],
      ),
    );
    if (type == null || !mounted) return;
    final id =
        '${type.wire}__n${DateTime.now().millisecondsSinceEpoch}';
    // 新內容預設 Draft + Internal（fail-closed 起點）。
    final draft = StudyContentItem(
      id: id,
      status: ContentStatus.draft,
      visibility: Visibility.internal,
      contentType: type,
      provenance: const ContentProvenance(source: 'native', note: 'admin_created'),
    );
    if (!mounted) return;
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => StudyContentEditor(item: draft, isNew: true)));
    ref.invalidate(adminStudyContentListProvider);
  }

  Future<void> _open(AdminStudyRow r) async {
    // 若目前 editorial 為 published（純 migrated-only 或已發佈狀態），走唯讀＋建新草稿。
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => StudyContentEditor(
                item: r.editorial,
                isNew: false,
                publishedLive: r.publishedLive)));
    ref.invalidate(adminStudyContentListProvider);
  }
}

// ============================ Study Content 編輯器 ============================

class StudyContentEditor extends ConsumerStatefulWidget {
  final StudyContentItem item;
  final bool isNew;
  final StudyContentItem? publishedLive;
  const StudyContentEditor(
      {super.key, required this.item, this.isNew = false, this.publishedLive});

  @override
  ConsumerState<StudyContentEditor> createState() => _StudyContentEditorState();
}

class _StudyContentEditorState extends ConsumerState<StudyContentEditor> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  late final TextEditingController _refs;
  late final TextEditingController _tags;
  late final Map<String, TextEditingController> _typed;
  late Visibility _visibility;
  // Church/Teacher R1：audience 為 authoring authority；visibility 由 audience 派生（相容）。
  late Audience _audience;
  late Set<String> _churchIds;
  late Set<String> _topicIds;
  bool _busy = false;

  StudyContentItem get it => widget.item;
  StudyContentType get type => it.contentType ?? StudyContentType.topicArticle;

  /// review 狀態下作者不得直接改內容；published 唯讀（須建新草稿）。
  bool get _readOnly =>
      it.status == ContentStatus.review ||
      it.status == ContentStatus.published ||
      it.status == ContentStatus.archived;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: it.title);
    _body = TextEditingController(text: it.body);
    _refs = TextEditingController(text: it.scriptureRefs.join('\n'));
    _tags = TextEditingController(text: it.tags.join(' '));
    _visibility = it.visibility ?? Visibility.internal;
    // audience：優先用既有；否則由 legacy visibility 派生（student→public、其餘→internal）。
    _audience = it.audience ??
        (it.visibility == Visibility.student ? Audience.public : Audience.internal);
    _churchIds = {...it.allowedChurchIds};
    _topicIds = {...it.topicIds};
    _typed = {
      for (final k in _typedFields(type))
        k: TextEditingController(text: _initTyped(k)),
    };
  }

  List<String> _typedFields(StudyContentType t) => switch (t) {
        StudyContentType.parallel => ['refs'],
        StudyContentType.type => ['otRef', 'ntRef', 'note'],
        StudyContentType.timeline => ['order', 'era', 'when', 'ref'],
        StudyContentType.person => ['aka', 'events'],
        StudyContentType.topicArticle => [],
      };

  String _initTyped(String k) {
    final d = it.data;
    switch (k) {
      case 'refs':
        return ((d['refs'] as List?) ?? const []).join('\n');
      case 'aka':
        return ((d['aka'] as List?) ?? const []).join('\n');
      case 'events':
        return [
          for (final e in (d['events'] as List?) ?? const [])
            '${(e as Map)['title'] ?? ''}|${e['ref'] ?? ''}'
        ].join('\n');
      case 'order':
        return '${d['order'] ?? ''}';
      default:
        return '${d[k] ?? ''}';
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _body, _refs, _tags, ..._typed.values]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.isNew ? '新增研讀內容' : '研讀內容')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _header(),
          const SizedBox(height: 12),
          if (_readOnly) _readOnlyBanner(),
          _field(_title, '標題', enabled: !_readOnly),
          _field(_body, '內文 / 說明', enabled: !_readOnly, lines: 5),
          _field(_refs, '經文引用（每行一個節位，例：約3:16）',
              enabled: !_readOnly, lines: 3),
          for (final k in _typedFields(type))
            _field(_typed[k]!, _typedLabel(k),
                enabled: !_readOnly, lines: k == 'events' ? 4 : 1),
          _field(_tags, '標籤（空格分隔）', enabled: !_readOnly),
          const SizedBox(height: 12),
          _visibilitySelector(),
          const SizedBox(height: 12),
          _topicPicker(),
          const SizedBox(height: 8),
          _provenanceRow(),
          const SizedBox(height: 20),
          ..._actions(),
        ],
      ),
    );
  }

  Widget _header() {
    final v = _readOnly ? it.visibility : _visibility;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(_title.text.isEmpty ? '(未命名)' : _title.text,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 4, children: [
        _pill(type.label, Colors.indigo),
        statusBadge(context, it.status),
        visibilityBadge(context, v),
        _pill('v${it.version}', Colors.grey),
      ]),
    ]);
  }

  Widget _readOnlyBanner() {
    final msg = it.status == ContentStatus.review
        ? '此版本正在「審核中」，作者不得直接修改內容。可退回或發布。'
        : '已發布／封存內容為唯讀。要修改（含改可見度）請「建立新版草稿」，不會動到現行版本。';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        const Icon(Icons.lock_outline, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(msg)),
      ]),
    );
  }

  String _typedLabel(String k) => {
        'refs': '平行經文（每行一個節位）',
        'otRef': '舊約預表經文',
        'ntRef': '新約應驗經文',
        'note': '說明',
        'order': '排序（數字）',
        'era': '分期',
        'when': '年代（文字）',
        'ref': '相關經文',
        'aka': '別名（每行一個）',
        'events': '重大事件（每行 標題|節位）',
      }[k] ??
      k;

  Widget _field(TextEditingController c, String label,
          {bool enabled = true, int lines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          enabled: enabled,
          minLines: lines,
          maxLines: lines == 1 ? 1 : lines + 3,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      );

  Widget _visibilitySelector() {
    final cur = _readOnly ? (it.audience ?? Audience.internal) : _audience;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('對象（audience）— 學生存取權的正式依據',
          style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      SegmentedButton<Audience>(
        segments: const [
          ButtonSegment(
              value: Audience.public,
              label: Text('公開'),
              icon: Icon(Icons.public)),
          ButtonSegment(
              value: Audience.church,
              label: Text('教會'),
              icon: Icon(Icons.church_outlined)),
          ButtonSegment(
              value: Audience.internal,
              label: Text('內部'),
              icon: Icon(Icons.lock_outline)),
        ],
        selected: {cur},
        onSelectionChanged:
            _readOnly ? null : (s) => setState(() => _audience = s.first),
      ),
      const SizedBox(height: 4),
      Text(
        switch (cur) {
          Audience.public => '發布後全體學生可在「研讀內容」取得。',
          Audience.church => '發布後只有所選教會的 Active 會員可取得。',
          Audience.internal => '即使發布，仍只供內部，學生不可見。',
        },
        style: Theme.of(context).textTheme.bodySmall,
      ),
      if (cur == Audience.church && !_readOnly) ...[
        const SizedBox(height: 8),
        _churchPicker(),
      ],
    ]);
  }

  Widget _churchPicker() {
    final churchesAsync = ref.watch(adminAllChurchesProvider);
    return churchesAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('教會載入失敗：$e'),
      data: (churches) {
        final active = churches.where((c) => c.active).toList();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('授權教會（只列 Active；Inactive 不可作為新對象）',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          if (active.isEmpty)
            const Text('尚無 Active 教會。請先在「教會與教師 → 教會」建立。',
                style: TextStyle(fontSize: 12)),
          Wrap(spacing: 6, children: [
            for (final c in active)
              FilterChip(
                label: Text(c.name.isEmpty ? c.id : c.name),
                selected: _churchIds.contains(c.id),
                onSelected: (sel) => setState(() =>
                    sel ? _churchIds.add(c.id) : _churchIds.remove(c.id)),
              ),
          ]),
          if (_churchIds.isEmpty)
            Text('⚠️ 教會對象需至少選一間，否則無法送審／發布。',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error, fontSize: 12)),
        ]);
      },
    );
  }

  Widget _topicPicker() {
    final topicsAsync = ref.watch(adminTopicListProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('主題（正式 study_topics）',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const Spacer(),
        TextButton.icon(
          icon: const Icon(Icons.add, size: 16),
          label: const Text('前往新增主題'),
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AdminTopicScreen())),
        ),
      ]),
      topicsAsync.when(
        loading: () => const LinearProgressIndicator(),
        error: (e, _) => Text('主題載入失敗：$e'),
        data: (rows) {
          if (rows.isEmpty) {
            return const Text('尚無主題。請先「前往新增主題」。');
          }
          final student = rows.where((r) => r.editorial.visibility == Visibility.student).toList();
          final internal = rows.where((r) => r.editorial.visibility != Visibility.student).toList();
          Widget group(String label, List<AdminTopicRow> rs) => rs.isEmpty
              ? const SizedBox.shrink()
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 2),
                      child: Text(label,
                          style: Theme.of(context).textTheme.labelSmall)),
                  Wrap(spacing: 6, children: [
                    for (final r in rs)
                      FilterChip(
                        label: Text(r.editorial.title.isEmpty
                            ? r.editorial.id
                            : r.editorial.title),
                        selected: _topicIds.contains(r.editorial.id),
                        onSelected: _readOnly
                            ? null
                            : (sel) => setState(() => sel
                                ? _topicIds.add(r.editorial.id)
                                : _topicIds.remove(r.editorial.id)),
                      ),
                  ]),
                ]);
          return Column(children: [
            group('學生可瀏覽的主題', student),
            group('內部主題', internal),
            if (_visibility == Visibility.student &&
                _topicIds.any((id) => internal.any((r) => r.editorial.id == id)))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                    '⚠️ 此內容為學生可見，但含內部主題；學生看得到此內容，但該內部主題不會成為學生可瀏覽的主題入口。',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12)),
              ),
          ]);
        },
      ),
    ]);
  }

  Widget _provenanceRow() => Row(children: [
        const Icon(Icons.info_outline, size: 16),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '來源：${it.provenance.source.isEmpty ? "native" : it.provenance.source}（系統資訊，不可編輯）',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ]);

  // ---- 動作 ----

  List<Widget> _actions() {
    final repo = ref.read(studyContentRepositoryProvider);
    final email = ref.read(adminEmailProvider);
    if (it.status == ContentStatus.published ||
        it.status == ContentStatus.archived) {
      return [
        FilledButton.icon(
          icon: const Icon(Icons.edit_note),
          label: const Text('建立新版草稿'),
          onPressed: _busy ? null : () => _run(() async {
            await repo.createContentDraftFromPublished(it.id, email);
            final draft = await repo.adminGetContentWorkspace(it.id);
            if (draft != null && mounted) {
              Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                      builder: (_) => StudyContentEditor(item: draft)));
            }
          }),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.history),
          label: const Text('版本紀錄'),
          onPressed: () => _showVersions(repo),
        ),
        if (it.status == ContentStatus.published) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            icon: const Icon(Icons.archive_outlined),
            label: const Text('封存（撤下，學生立即讀不到）'),
            onPressed: _busy
                ? null
                : () => _run(() async {
                      await repo.archiveContent(it.id, email);
                      if (mounted) Navigator.pop(context);
                    }),
          ),
        ],
      ];
    }
    if (it.status == ContentStatus.review) {
      // Reviewer：查看＋退回／發布（不得改內容）。
      return [
        FilledButton.icon(
          icon: const Icon(Icons.publish),
          label: const Text('發布…'),
          onPressed: _busy ? null : () => _publishFlow(repo, email),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.undo),
          label: const Text('退回草稿（需原因）'),
          onPressed: _busy ? null : () => _rejectFlow(repo, email),
        ),
      ];
    }
    // draft / rejected：可編輯 → 儲存草稿 / 送出審核
    return [
      FilledButton.icon(
        icon: const Icon(Icons.save_outlined),
        label: const Text('儲存草稿'),
        onPressed: _busy ? null : () => _run(() async {
          await _saveDraft(repo, email);
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('草稿已儲存')));
          }
        }),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        icon: const Icon(Icons.rate_review_outlined),
        label: const Text('送出審核…'),
        onPressed: _busy ? null : () => _submitFlow(repo, email),
      ),
    ];
  }

  Map<String, dynamic> _buildData() {
    final d = <String, dynamic>{};
    List<String> lines(String k) => _typed[k]!
        .text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    switch (type) {
      case StudyContentType.parallel:
        d['refs'] = lines('refs');
      case StudyContentType.type:
        d['otRef'] = _typed['otRef']!.text.trim();
        d['ntRef'] = _typed['ntRef']!.text.trim();
        d['note'] = _typed['note']!.text.trim();
      case StudyContentType.timeline:
        d['order'] = int.tryParse(_typed['order']!.text.trim()) ?? 0;
        d['era'] = _typed['era']!.text.trim();
        d['when'] = _typed['when']!.text.trim();
        d['ref'] = _typed['ref']!.text.trim();
      case StudyContentType.person:
        d['aka'] = lines('aka');
        d['events'] = [
          for (final l in lines('events'))
            {
              'title': l.split('|').first.trim(),
              'ref': l.contains('|') ? l.split('|')[1].trim() : ''
            }
        ];
      case StudyContentType.topicArticle:
        break;
    }
    return d;
  }

  Future<void> _saveDraft(StudyContentRepository repo, String email) async {
    final refs = _refs.text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final tags = _tags.text
        .split(RegExp(r'[\s,，#]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final payload = {
      'title': _title.text.trim(),
      'body': _body.text.trim(),
      'scripture_refs': refs,
      'topic_ids': _topicIds.toList(),
      'tags': tags,
      'data': _buildData(),
    };
    await repo.saveContentDraft(
      it.id,
      type: type,
      payload: payload,
      editorEmail: email,
      // audience 為 authoring authority；visibility 由 audience 派生（相容 legacy）。
      audience: _audience,
      allowedChurchIds: _audience == Audience.church ? _churchIds.toList() : const [],
      visibility:
          _audience == Audience.public ? Visibility.student : Visibility.internal,
      provenance: it.provenance,
    );
    ref.invalidate(adminStudyContentListProvider);
  }

  String _audienceMeaning(Audience a) => switch (a) {
        Audience.public => '此版本若審核通過並發布，全體學生可在「研讀內容」取得。',
        Audience.church => '此版本發布後，只有所選教會的 Active 會員可取得。',
        Audience.internal => '此版本即使發布，仍不會出現在學生「研讀內容」。',
      };

  Future<void> _submitFlow(StudyContentRepository repo, String email) async {
    if (_audience == Audience.church && _churchIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('教會對象需至少選一間教會，才能送審。')));
      return;
    }
    final ok = await _confirm(
      title: '送出審核',
      body:
          '型別：${type.label}\n標題：${_title.text.trim()}\n對象：${_audience.label}${_audience == Audience.church ? '（${_churchIds.length} 間教會）' : ''}\n\n此內容將進入「審核中」。\n\n${_audienceMeaning(_audience)}',
      confirm: '確認送審',
    );
    if (ok != true) return;
    await _run(() async {
      await _saveDraft(repo, email); // 先存最新編輯
      await repo.submitContentForReview(it.id, email);
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _publishFlow(StudyContentRepository repo, String email) async {
    final aud = it.audience ?? Audience.internal;
    final title = switch (aud) {
      Audience.public => '發布並開放學生',
      Audience.church => '發布給指定教會',
      Audience.internal => '發布為內部內容',
    };
    // Public/擴大曝光警語（Church/Internal → Public）。
    final expanding = aud == Audience.public;
    final ok = await _confirm(
      title: title,
      body: '發布狀態：Published\n對象：${aud.label}\n\n${_audienceMeaning(aud)}'
          '${expanding ? "\n\n⚠️ 這是「公開」內容——發布後全體學生（含未加入教會者）都可讀取。" : ""}',
      confirm: title,
    );
    if (ok != true) return;
    await _run(() async {
      await repo.publishContent(it.id, email);
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _rejectFlow(StudyContentRepository repo, String email) async {
    final reason = await _promptReason();
    if (reason == null) return;
    await _run(() async {
      // 退回原因寫回 workspace draft 的 provenance note（保留可追溯）。
      await repo.rejectContent(it.id, email);
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _showVersions(StudyContentRepository repo) async {
    final versions = await repo.adminContentVersions(it.id);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('版本紀錄'),
        content: SizedBox(
          width: 400,
          child: versions.isEmpty
              ? const Text('尚無歷史版本快照。')
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final v in versions)
                      ListTile(
                        dense: true,
                        title: Text('v${v['version'] ?? v['_vid']}'),
                        subtitle: Text(
                            '狀態：${v['status']}｜可見度：${v['visibility'] ?? 'internal'}\n'
                            '發布：${v['published_by'] ?? ''}\n審核：${v['reviewed_by'] ?? ''}'),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('關閉'))
        ],
      ),
    );
  }

  Future<bool?> _confirm(
          {required String title,
          required String body,
          required String confirm}) =>
      showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(confirm)),
          ],
        ),
      );

  Future<String?> _promptReason() {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('退回原因'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(hintText: '請說明退回原因'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, c.text.trim()),
              child: const Text('退回')),
        ],
      ),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('操作失敗：$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

// ============================ Topic Admin ============================

class AdminTopicScreen extends ConsumerWidget {
  const AdminTopicScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rowsAsync = ref.watch(adminTopicListProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('主題')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('新增主題'),
        onPressed: () => _openEditor(context, ref, null),
      ),
      body: rowsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('載入失敗：$e')),
        data: (rows) => rows.isEmpty
            ? const Center(
                child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('尚無主題。右下角可新增。')))
            : ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final t = rows[i].editorial;
                  return ListTile(
                    title: Text(t.title.isEmpty ? '(未命名)' : t.title,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(spacing: 6, runSpacing: 4, children: [
                        _pill('slug: ${t.id}', Colors.grey),
                        statusBadge(context, t.status),
                        visibilityBadge(context, t.visibility),
                        _pill('排序 ${t.sortOrder}', Colors.teal),
                        _pill('v${t.version}', Colors.grey),
                      ]),
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openEditor(context, ref, rows[i]),
                  );
                },
              ),
      ),
    );
  }

  void _openEditor(BuildContext context, WidgetRef ref, AdminTopicRow? row) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => TopicEditor(row: row))).then(
        (_) => ref.invalidate(adminTopicListProvider));
  }
}

class TopicEditor extends ConsumerStatefulWidget {
  final AdminTopicRow? row;
  const TopicEditor({super.key, this.row});

  @override
  ConsumerState<TopicEditor> createState() => _TopicEditorState();
}

class _TopicEditorState extends ConsumerState<TopicEditor> {
  late final TextEditingController _title;
  late final TextEditingController _slug;
  late final TextEditingController _desc;
  late final TextEditingController _sort;
  late Audience _audience;
  late Set<String> _churchIds;
  bool _busy = false;

  StudyTopic? get t => widget.row?.editorial;
  bool get _isNew => widget.row == null;
  bool get _readOnly =>
      t != null &&
      (t!.status == ContentStatus.review ||
          t!.status == ContentStatus.published ||
          t!.status == ContentStatus.archived);

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: t?.title ?? '');
    _slug = TextEditingController(text: t?.id ?? '');
    _desc = TextEditingController(text: t?.description ?? '');
    _sort = TextEditingController(text: '${t?.sortOrder ?? 0}');
    _audience = t?.audience ??
        (t?.visibility == Visibility.student ? Audience.public : Audience.internal);
    _churchIds = {...(t?.allowedChurchIds ?? const [])};
  }

  @override
  void dispose() {
    for (final c in [_title, _slug, _desc, _sort]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isNew ? '新增主題' : '主題')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (t != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Wrap(spacing: 6, children: [
              statusBadge(context, t!.status),
              visibilityBadge(context, t!.visibility),
              _pill('v${t!.version}', Colors.grey),
            ]),
          ),
        if (_readOnly)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
                t!.status == ContentStatus.review
                    ? '審核中，作者不得直接修改。'
                    : '已發布／封存為唯讀；要改（含改可見度）請「建立新版草稿」。',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        TextField(
          controller: _slug,
          enabled: _isNew, // slug/id 建立後不可改（可能被 references 使用）
          decoration: const InputDecoration(
              labelText: 'Slug / ID（建立後不可改）',
              border: OutlineInputBorder(),
              isDense: true),
        ),
        const SizedBox(height: 12),
        _tf(_title, '標題', enabled: !_readOnly),
        _tf(_desc, '描述', enabled: !_readOnly, lines: 3),
        _tf(_sort, '排序（數字）', enabled: !_readOnly),
        const SizedBox(height: 12),
        const Text('對象（audience）', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        SegmentedButton<Audience>(
          segments: const [
            ButtonSegment(value: Audience.public, label: Text('公開')),
            ButtonSegment(value: Audience.church, label: Text('教會')),
            ButtonSegment(value: Audience.internal, label: Text('內部')),
          ],
          selected: {_readOnly ? (t!.audience ?? Audience.internal) : _audience},
          onSelectionChanged:
              _readOnly ? null : (s) => setState(() => _audience = s.first),
        ),
        if (!_readOnly && _audience == Audience.church) ...[
          const SizedBox(height: 6),
          _topicChurchPicker(),
        ],
        const SizedBox(height: 20),
        ..._actions(),
      ]),
    );
  }

  Widget _tf(TextEditingController c, String label,
          {bool enabled = true, int lines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          enabled: enabled,
          minLines: lines,
          maxLines: lines == 1 ? 1 : lines + 2,
          decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              isDense: true),
        ),
      );

  List<Widget> _actions() {
    final repo = ref.read(studyContentRepositoryProvider);
    final email = ref.read(adminEmailProvider);
    final status = t?.status;
    if (status == ContentStatus.published || status == ContentStatus.archived) {
      return [
        FilledButton.icon(
          icon: const Icon(Icons.edit_note),
          label: const Text('建立新版草稿'),
          onPressed: _busy
              ? null
              : () => _run(() async {
                    await repo.createTopicDraftFromPublished(t!.id, email);
                    final draft = await repo.adminGetTopicWorkspace(t!.id);
                    if (draft != null && mounted) {
                      Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                              builder: (_) => TopicEditor(
                                  row: AdminTopicRow(editorial: draft))));
                    }
                  }),
        ),
        if (status == ContentStatus.published) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            icon: const Icon(Icons.archive_outlined),
            label: const Text('封存'),
            onPressed: _busy
                ? null
                : () => _run(() async {
                      await repo.archiveTopic(t!.id, email);
                      if (mounted) Navigator.pop(context);
                    }),
          ),
        ],
      ];
    }
    if (status == ContentStatus.review) {
      return [
        FilledButton.icon(
          icon: const Icon(Icons.publish),
          label: Text(t!.visibility == Visibility.student
              ? '發布並開放學生'
              : '發布為內部主題'),
          onPressed: _busy
              ? null
              : () => _run(() async {
                    final student = t!.visibility == Visibility.student;
                    final ok = await _confirm(
                        student ? '發布並開放學生' : '發布為內部主題',
                        student
                            ? '發布後此主題可成為學生可瀏覽的主題入口。'
                            : '發布後仍只供內部，不會出現在學生主題。');
                    if (ok != true) return;
                    await repo.publishTopic(t!.id, email);
                    if (mounted) Navigator.pop(context);
                  }),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.undo),
          label: const Text('退回草稿'),
          onPressed: _busy
              ? null
              : () => _run(() async {
                    await repo.rejectTopic(t!.id, email);
                    if (mounted) Navigator.pop(context);
                  }),
        ),
      ];
    }
    // new / draft / rejected
    return [
      FilledButton.icon(
        icon: const Icon(Icons.save_outlined),
        label: const Text('儲存草稿'),
        onPressed: _busy ? null : () => _run(() => _save(repo, email, snack: true)),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        icon: const Icon(Icons.rate_review_outlined),
        label: const Text('送出審核'),
        onPressed: _busy
            ? null
            : () => _run(() async {
                  final id = await _save(repo, email);
                  await repo.submitTopicForReview(id, email);
                  if (mounted) Navigator.pop(context);
                }),
      ),
    ];
  }

  Widget _topicChurchPicker() {
    final churchesAsync = ref.watch(adminAllChurchesProvider);
    return churchesAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('教會載入失敗：$e'),
      data: (all) {
        final active = all.where((c) => c.active).toList();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('授權教會（只列 Active）',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          Wrap(spacing: 6, children: [
            for (final c in active)
              FilterChip(
                label: Text(c.name.isEmpty ? c.id : c.name),
                selected: _churchIds.contains(c.id),
                onSelected: (sel) => setState(() =>
                    sel ? _churchIds.add(c.id) : _churchIds.remove(c.id)),
              ),
          ]),
          if (_churchIds.isEmpty)
            Text('⚠️ 教會對象需至少一間，否則無法送審／發布。',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error, fontSize: 12)),
        ]);
      },
    );
  }

  Future<String> _save(StudyContentRepository repo, String email,
      {bool snack = false}) async {
    final id = _isNew
        ? (_slug.text.trim().isEmpty
            ? 'topic__${DateTime.now().millisecondsSinceEpoch}'
            : _slug.text.trim())
        : t!.id;
    await repo.saveTopicDraft(
      id,
      payload: {
        'title': _title.text.trim(),
        'description': _desc.text.trim(),
        'sort_order': int.tryParse(_sort.text.trim()) ?? 0,
      },
      editorEmail: email,
      audience: _audience,
      allowedChurchIds: _audience == Audience.church ? _churchIds.toList() : const [],
      visibility:
          _audience == Audience.public ? Visibility.student : Visibility.internal,
    );
    ref.invalidate(adminTopicListProvider);
    if (snack && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('主題草稿已儲存')));
    }
    return id;
  }

  Future<bool?> _confirm(String title, String body) => showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(title)),
          ],
        ),
      );

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('操作失敗：$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
