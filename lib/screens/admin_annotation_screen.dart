import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../models/managed_content.dart';
import '../services/annotation_admin_repository.dart';
import '../providers/providers.dart';

/// 後台「節註解（多版本／audience）」管理——**同一節可有多筆**：public、church（各教會）
/// 各自獨立 doc，互不覆寫。走既有 managed-content workflow（Draft→Review→Published）。
/// ⛔ 內容仍由使用者親撰；此檔只維護編輯器與 audience 授權 UI。

/// 某節的所有 annotation 清單（多版本）。
class AdminVerseAnnotationsScreen extends ConsumerWidget {
  final Book book;
  final int chapter;
  final int verse;
  const AdminVerseAnnotationsScreen({
    super.key,
    required this.book,
    required this.chapter,
    required this.verse,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = book.chapters[chapter - 1][verse - 1];
    final rows = ref.watch(adminVerseAnnotationsProvider(
        (book: book.id, chapter: chapter, verse: verse)));
    return Scaffold(
      appBar: AppBar(title: Text('${book.name} $chapter:$verse · 註解版本')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('新增註解'),
        onPressed: () => _openEditor(context, ref, null, Audience.internal),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text('「$text」', style: const TextStyle(height: 1.6)),
            ),
          ),
          const SizedBox(height: 8),
          Text('同一節可有多筆註解（公開＋各教會各自獨立，互不覆寫）',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          rows.when(
            loading: () =>
                const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => Text('載入失敗：$e'),
            data: (list) => list.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('此節尚無任何註解。點右下角「新增註解」建立。'))
                : Column(
                    children: [
                      for (final r in list)
                        Card(
                          child: ListTile(
                            title: Row(children: [
                              _audienceBadge(context, r.audienceName),
                              const SizedBox(width: 8),
                              _statusBadge(context, r.status),
                            ]),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                (r.payload['commentary'] as String?)?.trim().isNotEmpty == true
                                    ? r.payload['commentary'] as String
                                    : '（尚無字義內容）',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _openEditor(
                                context,
                                ref,
                                r.id,
                                _audienceOf(r.audienceName)),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  void _openEditor(BuildContext context, WidgetRef ref, String? annotationId,
      Audience audience) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminAnnotationEditor(
          book: book,
          chapter: chapter,
          verse: verse,
          annotationId: annotationId,
          initialAudience: audience,
        ),
      ),
    ).then((_) => ref.invalidate(adminVerseAnnotationsProvider(
        (book: book.id, chapter: chapter, verse: verse))));
  }
}

Audience _audienceOf(String? name) => switch (name) {
      'public' => Audience.public,
      'church' => Audience.church,
      _ => Audience.internal,
    };

Widget _audienceBadge(BuildContext context, String? name) {
  final a = _audienceOf(name);
  final (label, color) = switch (a) {
    Audience.public => ('公開', Colors.teal),
    Audience.church => ('教會', Theme.of(context).colorScheme.primary),
    Audience.internal => ('內部', Colors.grey),
  };
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8)),
    child: Text(label, style: TextStyle(color: color, fontSize: 12)),
  );
}

Widget _statusBadge(BuildContext context, String status) {
  final label = switch (status) {
    'published' => '已發布',
    'review' => '審核中',
    'rejected' => '已退回',
    'archived' => '已封存',
    _ => '草稿',
  };
  return Text(label, style: Theme.of(context).textTheme.labelSmall);
}

/// 單筆註解編輯器：欄位 + audience 選擇 + church picker + workflow。
class AdminAnnotationEditor extends ConsumerStatefulWidget {
  final Book book;
  final int chapter;
  final int verse;
  final String? annotationId; // null＝新增
  final Audience initialAudience;
  const AdminAnnotationEditor({
    super.key,
    required this.book,
    required this.chapter,
    required this.verse,
    required this.annotationId,
    required this.initialAudience,
  });

  @override
  ConsumerState<AdminAnnotationEditor> createState() =>
      _AdminAnnotationEditorState();
}

class _AdminAnnotationEditorState extends ConsumerState<AdminAnnotationEditor> {
  final _commentary = TextEditingController();
  final _keywords = TextEditingController();
  final _background = TextEditingController();
  final _category = TextEditingController();
  final _application = TextEditingController();
  final _crossRefs = TextEditingController();

  Audience _audience = Audience.internal;
  final Set<String> _churchIds = {};
  String? _annotationId;
  ContentStatus _status = ContentStatus.draft;
  bool _hasWorkspaceDraft = false; // 有可編輯的 workspace 草稿
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _annotationId = widget.annotationId;
    _audience = widget.initialAudience;
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(annotationAdminRepositoryProvider);
    try {
      ManagedContent? c;
      if (_annotationId != null) {
        c = await repo.getWorkspace(_annotationId!);
        _hasWorkspaceDraft = c != null && c.status != ContentStatus.published;
        c ??= await repo.getPublished(_annotationId!);
      }
      if (c != null) {
        _status = c.status;
        _audience = c.audience ?? Audience.internal;
        _churchIds
          ..clear()
          ..addAll(c.allowedChurchIds);
        _fillFields(c.payload);
      }
    } catch (_) {
      // 從空白開始
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _fillFields(Map<String, dynamic> p) {
    _commentary.text = (p['commentary'] as String?) ?? '';
    _keywords.text = ((p['keywords'] as List?) ?? const [])
        .map((e) => '${(e as Map)['word']}｜${e['note']}')
        .join('\n');
    _background.text = (p['background'] as String?) ?? '';
    final app = p['application'] as Map<String, dynamic>?;
    _category.text = (app?['category'] as String?) ?? '';
    _application.text = (app?['text'] as String?) ?? '';
    _crossRefs.text =
        ((p['crossRefs'] as List?) ?? const []).map((e) => '$e').join(', ');
  }

  Map<String, dynamic> _payload() {
    final keywords = _splitLines(_keywords.text)
        .map((line) {
          final parts = line.split(RegExp(r'[｜|]'));
          if (parts.length < 2) return null;
          return {
            'word': parts[0].trim(),
            'note': parts.sublist(1).join('｜').trim(),
          };
        })
        .whereType<Map<String, String>>()
        .toList();
    final crossRefs = _crossRefs.text
        .split(RegExp(r'[,，、]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return {
      if (_commentary.text.trim().isNotEmpty) 'commentary': _commentary.text.trim(),
      if (keywords.isNotEmpty) 'keywords': keywords,
      if (_background.text.trim().isNotEmpty) 'background': _background.text.trim(),
      if (_application.text.trim().isNotEmpty)
        'application': {
          if (_category.text.trim().isNotEmpty) 'category': _category.text.trim(),
          'text': _application.text.trim(),
        },
      if (crossRefs.isNotEmpty) 'crossRefs': crossRefs,
    };
  }

  bool get _readOnly =>
      _status == ContentStatus.published && !_hasWorkspaceDraft;

  String get _email => ref.read(adminEmailProvider);

  Future<void> _run(Future<void> Function() action, String okMsg) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(okMsg)));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('失敗：$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _validateChurch() {
    if (_audience == Audience.church && _churchIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('教會對象需至少選一間教會，才能儲存草稿／送審／發布。')));
      return false;
    }
    return true;
  }

  Future<void> _saveDraft() async {
    if (!_validateChurch()) return;
    final repo = ref.read(annotationAdminRepositoryProvider);
    _annotationId ??= AnnotationAdminRepository.newAnnotationId(
        widget.book.id, widget.chapter, widget.verse, _audience,
        churchId: _churchIds.isEmpty ? null : _churchIds.first);
    await _run(
        () => repo.saveDraft(_annotationId!,
            book: widget.book.id,
            chapter: widget.chapter,
            verse: widget.verse,
            payload: _payload(),
            audience: _audience,
            allowedChurchIds:
                _audience == Audience.church ? _churchIds.toList() : const [],
            editorEmail: _email),
        '已儲存草稿');
  }

  Future<void> _submit() async {
    if (!_validateChurch()) return;
    // 先存草稿確保最新內容進 workspace，再送審。
    final repo = ref.read(annotationAdminRepositoryProvider);
    _annotationId ??= AnnotationAdminRepository.newAnnotationId(
        widget.book.id, widget.chapter, widget.verse, _audience,
        churchId: _churchIds.isEmpty ? null : _churchIds.first);
    final expo = _audience == Audience.public
        ? '\n\n⚠️ 這是「公開」內容——發布後全體學生（含未加入教會者）皆可讀取。'
        : '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('送審'),
        content: Text(
            '對象：${_audience.label}${_audience == Audience.church ? '（${_churchIds.length} 間教會）' : ''}\n'
            '${switch (_audience) {
          Audience.public => '審核通過並發布後，全體學生可讀。',
          Audience.church => '發布後只有所選教會的 Active 會員可讀。',
          Audience.internal => '即使發布，學生也不可見。',
        }}$expo'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('送審')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await repo.saveDraft(_annotationId!,
          book: widget.book.id,
          chapter: widget.chapter,
          verse: widget.verse,
          payload: _payload(),
          audience: _audience,
          allowedChurchIds:
              _audience == Audience.church ? _churchIds.toList() : const [],
          editorEmail: _email);
      await repo.submitForReview(_annotationId!, _email);
    }, '已送審');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final repo = ref.read(annotationAdminRepositoryProvider);
    return Scaffold(
      appBar: AppBar(
          title: Text(
              '${widget.book.name} ${widget.chapter}:${widget.verse} · 註解編輯')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_readOnly)
              Card(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('此註解為「已發布」，唯讀。改內容或改 audience 請「建立新版草稿」。'),
                ),
              ),
            const SizedBox(height: 8),
            _audienceSection(),
            const SizedBox(height: 16),
            _field(_commentary, '注釋／字義（這句背後的意義）', maxLines: 5),
            _field(_keywords, '關鍵字（每行一個，格式：詞｜解釋）', maxLines: 5),
            _field(_background, '背景（歷史／文化背景）', maxLines: 4),
            _field(_category, '生活應用分類（例：信心）', maxLines: 1),
            _field(_application, '生活應用建議', maxLines: 4),
            _field(_crossRefs, '相關經文（逗號分隔，例：約1:1, 詩33:6）', maxLines: 2),
            const SizedBox(height: 20),
            if (_readOnly)
              FilledButton.icon(
                icon: const Icon(Icons.edit_document),
                label: const Text('建立新版草稿'),
                onPressed: () => _run(
                    () => repo.createDraftFromPublished(_annotationId!, _email),
                    '已從已發布建立新版草稿，回列表後可編輯'),
              )
            else ...[
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton.icon(
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('存草稿'),
                    onPressed: _saveDraft),
                if (_status == ContentStatus.review) ...[
                  OutlinedButton.icon(
                      icon: const Icon(Icons.undo),
                      label: const Text('退回'),
                      onPressed: () => _run(
                          () => repo.reject(_annotationId!, _email), '已退回草稿')),
                  FilledButton.icon(
                      icon: const Icon(Icons.publish),
                      label: const Text('發布'),
                      onPressed: () {
                        if (!_validateChurch()) return;
                        _run(() => repo.publish(_annotationId!, _email), '已發布');
                      }),
                ] else
                  FilledButton.icon(
                      icon: const Icon(Icons.rate_review_outlined),
                      label: const Text('送審'),
                      onPressed: _submit),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _audienceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('對象（audience）— 學生存取權的正式依據',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        SegmentedButton<Audience>(
          segments: const [
            ButtonSegment(value: Audience.public, label: Text('公開')),
            ButtonSegment(value: Audience.church, label: Text('教會')),
            ButtonSegment(value: Audience.internal, label: Text('內部')),
          ],
          selected: {_audience},
          onSelectionChanged:
              _readOnly ? null : (s) => setState(() => _audience = s.first),
        ),
        const SizedBox(height: 4),
        Text(
          switch (_audience) {
            Audience.public => '發布後全體學生（含未加入教會者）皆可讀。',
            Audience.church => '發布後只有所選教會的 Active 會員可讀。',
            Audience.internal => '預設。即使發布，學生也不可見。',
          },
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (_audience == Audience.church && !_readOnly) ...[
          const SizedBox(height: 8),
          _churchPicker(),
        ],
      ],
    );
  }

  Widget _churchPicker() {
    final churches = ref.watch(activeChurchesProvider);
    return churches.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('教會載入失敗：$e'),
      data: (list) {
        if (list.isEmpty) {
          return const Text('尚無 Active 教會。請先在「教會與教師 → 教會」建立。',
              style: TextStyle(color: Colors.red));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('授權教會（只列 Active；Inactive 不可作為新對象）',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                for (final c in list)
                  FilterChip(
                    label: Text(c.name),
                    selected: _churchIds.contains(c.id),
                    onSelected: (s) => setState(() =>
                        s ? _churchIds.add(c.id) : _churchIds.remove(c.id)),
                  ),
              ],
            ),
            if (_churchIds.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('⚠️ 教會對象需至少選一間，否則無法送審／發布。',
                    style: TextStyle(color: Colors.red)),
              ),
          ],
        );
      },
    );
  }

  Widget _field(TextEditingController c, String label, {int maxLines = 3}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          readOnly: _readOnly,
          maxLines: maxLines,
          decoration: InputDecoration(
              labelText: label, border: const OutlineInputBorder()),
        ),
      );

  @override
  void dispose() {
    for (final c in [
      _commentary,
      _keywords,
      _background,
      _category,
      _application,
      _crossRefs
    ]) {
      c.dispose();
    }
    super.dispose();
  }
}

List<String> _splitLines(String s) =>
    s.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
