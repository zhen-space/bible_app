import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/managed_content.dart';
import '../providers/providers.dart';
import '../services/verse_locator.dart';
import '../utils/date_key.dart';
import 'admin_study_content_screen.dart' show statusBadge;

/// 每日經文後台。workflow：Draft→Review→Published（+Rejected/Archived），
/// 沿用 ContentWorkflowService，型別 'daily_verses'、**contentId = 日期（YYYY-MM-DD）**。
/// doc id＝日期 ⇒ **每個日期至多一筆對外版本（one active per date 為結構不變量）**；
/// 要換內容＝從現行版本「建立替代草稿」→審核→發布（版本 +1、舊版入 versions）。
/// 學生端只在 date==today 且 published 顯示；未來日期先發布不會提前出現（fail-closed）。
class AdminDailyVerseScreen extends ConsumerStatefulWidget {
  const AdminDailyVerseScreen({super.key});

  static const _type = 'daily_verses';

  @override
  ConsumerState<AdminDailyVerseScreen> createState() =>
      _AdminDailyVerseScreenState();
}

class _AdminDailyVerseScreenState extends ConsumerState<AdminDailyVerseScreen> {
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final listAsync = ref.watch(adminDailyVerseListProvider);
    final filter = _filter;
    final todayYmd = taipeiTodayYmd(); // §A5：權威日期鍵＝Asia/Taipei（非裝置時區）
    return Scaffold(
      appBar: AppBar(title: const Text('每日經文')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('新增每日經文'),
        onPressed: () => _openEditor(context, ref, null),
      ),
      body: listAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('載入失敗：$e')),
        data: (rows) {
          // §A11：今日無服務中 Published（date==today 且 status==published）→ 高可見度警示。
          final hasTodayPublished = rows.any((r) =>
              r['_date'] == todayYmd && r['_published_status'] == 'published');
          final filtered =
              rows.where((r) => _matchesFilter(r, filter)).toList();
          return Column(children: [
            _FilterBar(
                value: _filter,
                onChanged: (v) => setState(() => _filter = v)),
            if (!hasTodayPublished)
              Container(
                width: double.infinity,
                color: Theme.of(context).colorScheme.errorContainer,
                padding: const EdgeInsets.all(12),
                child: Text('⚠️ 今日（$todayYmd，台北）尚無服務中的 Published 每日經文，學生首頁將顯示「今日經文尚未提供」。',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer)),
              ),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text('此篩選下沒有每日經文。')))
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) =>
                          _row(context, ref, filtered[i], todayYmd),
                    ),
            ),
          ]);
        },
      ),
    );
  }

  Widget _row(BuildContext context, WidgetRef ref, Map<String, dynamic> r,
      String todayYmd) {
    final date = r['_date'] as String;
    final status = ContentStatus.fromName(r['status'] as String?);
    final when = date.compareTo(todayYmd) == 0
        ? '今天'
        : (date.compareTo(todayYmd) > 0 ? '未來' : '過去');
    final hasReplacementDraft = r['_has_published'] == true &&
        status != ContentStatus.published &&
        status != ContentStatus.archived;
    final pubVer = r['_published_version'];
    final pubBy = r['_published_by'];
    final pubAt = r['_published_at'];
    String d(dynamic ms) => ms is int && ms > 0
        ? DateTime.fromMillisecondsSinceEpoch(ms).toString().substring(0, 16)
        : '—';
    return ListTile(
      title: Text('$date · $when',
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            statusBadge(context, status),
            Text(_scriptureText(r)),
            if (hasReplacementDraft)
              Text('· 有新版草稿（服務中仍為現行 Published）',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600)),
          ]),
          // 現行服務中的 Published 版本 + publishedAt/publisher。
          if (r['_published_status'] == 'published' && pubVer != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('服務中 Published v$pubVer · ${pubBy ?? '—'} · ${d(pubAt)}',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
        ]),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _openEditor(context, ref, r),
    );
  }

  /// 依編輯真相 status（+ 是否有服務中 Published）過濾。
  bool _matchesFilter(Map<String, dynamic> r, String filter) {
    final status = (r['status'] as String?) ?? 'draft';
    switch (filter) {
      case 'draft_review':
        return status == 'draft' || status == 'review';
      case 'published':
        return r['_published_status'] == 'published';
      case 'rejected':
        return status == 'rejected';
      case 'archived':
        return status == 'archived' || r['_published_status'] == 'archived';
      default:
        return true;
    }
  }

  static String _scriptureText(Map<String, dynamic> r) {
    final b = r['book_id'], c = r['chapter'], v = r['verse'];
    if (b == null) return '(未設定經文)';
    final rt = r['ref_text'];
    return (rt is String && rt.isNotEmpty) ? rt : '書$b $c:$v';
  }

  void _openEditor(
      BuildContext context, WidgetRef ref, Map<String, dynamic>? row) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DailyVerseEditor(row: row)),
    ).then((_) => ref.invalidate(adminDailyVerseListProvider));
  }
}

/// 清單狀態過濾列（全部／草稿·審核／已發布／已退回／已封存）。
class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    const opts = [
      ('all', '全部'),
      ('draft_review', '草稿/審核'),
      ('published', '已發布'),
      ('rejected', '已退回'),
      ('archived', '已封存'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(children: [
        for (final (val, label) in opts)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(label),
              selected: value == val,
              onSelected: (_) => onChanged(val),
            ),
          ),
      ]),
    );
  }
}

class DailyVerseEditor extends ConsumerStatefulWidget {
  final Map<String, dynamic>? row;
  const DailyVerseEditor({super.key, this.row});

  @override
  ConsumerState<DailyVerseEditor> createState() => _DailyVerseEditorState();
}

class _DailyVerseEditorState extends ConsumerState<DailyVerseEditor> {
  late DateTime _date;
  late final TextEditingController _ref;
  late final TextEditingController _title;
  late final TextEditingController _content;
  bool _busy = false;

  Map<String, dynamic>? get row => widget.row;
  bool get _isNew => row == null;
  ContentStatus get _status =>
      ContentStatus.fromName(row?['status'] as String?);
  bool get _hasPublished => row?['_has_published'] == true;
  bool get _readOnly =>
      !_isNew &&
      (_status == ContentStatus.review ||
          _status == ContentStatus.published ||
          _status == ContentStatus.archived);

  @override
  void initState() {
    super.initState();
    final d = row?['_date'] as String?;
    // 新建預設＝台北今日（非裝置時區；避免跨午夜選錯日）。
    _date = d != null ? DateTime.parse(d) : DateTime.parse(taipeiTodayYmd());
    // 以既存的節位字串回填（若無則空，等使用者輸入）。
    _ref = TextEditingController(text: (row?['ref_text'] as String?) ?? '');
    _title = TextEditingController(text: (row?['title'] as String?) ?? '');
    _content = TextEditingController(text: (row?['content'] as String?) ?? '');
  }

  @override
  void dispose() {
    _ref.dispose();
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  String get _ymd =>
      '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isNew ? '新增每日經文' : '每日經文 · $_ymd')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (!_isNew)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: statusBadge(context, _status),
          ),
        if (_readOnly)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
                _status == ContentStatus.review
                    ? '審核中，作者不得直接修改。'
                    : '已發布／封存為唯讀。要更換此日經文，請「建立替代草稿」（發布後取代現行版本）。',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event),
          title: Text('日期：$_ymd'),
          subtitle: const Text('doc id＝日期，每個日期至多一筆對外版本'),
          trailing: _isNew ? const Icon(Icons.edit) : null,
          onTap: _isNew ? _pickDate : null,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _ref,
          enabled: !_readOnly,
          decoration: const InputDecoration(
            labelText: '經文節位（正式識別，例：約3:16）',
            helperText: '以節位為識別，不只是貼上經文文字',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _title,
          enabled: !_readOnly,
          decoration: const InputDecoration(
              labelText: '標題（選填）',
              border: OutlineInputBorder(),
              isDense: true),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _content,
          enabled: !_readOnly,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
              labelText: '內容 / 引言（選填）',
              border: OutlineInputBorder(),
              isDense: true),
        ),
        if (_hasPublished && !_readOnly)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('此日期已有發布版本；發布此草稿將取代它（版本 +1，舊版入版本紀錄）。',
                style: Theme.of(context).textTheme.bodySmall),
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('預覽學生首頁'),
          onPressed: _preview,
        ),
        const SizedBox(height: 20),
        ..._actions(),
        _versionHistory(),
      ]),
    );
  }

  /// A17 學生首頁預覽（不寫入、不改狀態、不發布；用目前草稿 snapshot＋正式 Bible 經文）。
  Future<void> _preview() async {
    final books = ref.read(booksProvider).value ?? const [];
    final parsed = VerseLocator.parse(_ref.text.trim(), books);
    String verseText = '（無法解析經文節位）';
    String refDisplay = _ref.text.trim();
    if (parsed != null && parsed.verse != null) {
      final book = books.firstWhere((b) => b.id == parsed.bookId,
          orElse: () => books.first);
      final ci = parsed.chapter - 1, vi = parsed.verse! - 1;
      if (ci >= 0 &&
          ci < book.chapters.length &&
          vi >= 0 &&
          vi < book.chapters[ci].length) {
        verseText = book.chapters[ci][vi];
      }
      refDisplay = '${book.name} ${parsed.chapter}:${parsed.verse}';
    }
    if (!mounted) return;
    final title = _title.text.trim();
    final content = _content.text.trim();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('學生首頁預覽',
                style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title.isNotEmpty) ...[
                      Text(title,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                    ],
                    Text(verseText,
                        style: const TextStyle(fontSize: 16, height: 1.6)),
                    const SizedBox(height: 8),
                    Text(refDisplay,
                        style: Theme.of(context).textTheme.bodySmall),
                    if (content.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(content, style: const TextStyle(height: 1.6)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A16 版本紀錄（唯讀）。
  Widget _versionHistory() {
    final versions = (row?['_versions'] as List?) ?? const [];
    final curV = row?['_published_version'];
    if (versions.isEmpty && curV == null) return const SizedBox.shrink();
    String d(dynamic ms) => ms is int && ms > 0
        ? DateTime.fromMillisecondsSinceEpoch(ms)
            .toString()
            .substring(0, 16)
        : '—';
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('版本紀錄', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        if (curV != null)
          ListTile(
            dense: true,
            leading: const Icon(Icons.verified, size: 18),
            title: Text('v$curV（現行 Published）'),
            subtitle: Text(
                '發布：${row?['_published_by'] ?? '—'} · ${d(row?['_published_at'])}'),
          ),
        for (final v in versions.reversed)
          ListTile(
            dense: true,
            leading: const Icon(Icons.history, size: 18),
            title: Text('v${(v as Map)['version'] ?? '?'} · ${v['status'] ?? '—'}'),
            subtitle: Text(
                '經文 ${v['ref_text'] ?? '書${v['book_id']} ${v['chapter']}:${v['verse']}'} · 發布 ${d(v['published_at'])}'),
          ),
      ]),
    );
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _date = d);
  }

  List<Widget> _actions() {
    final wf = ref.read(contentWorkflowServiceProvider);
    final email = ref.read(adminEmailProvider);
    const type = AdminDailyVerseScreen._type;

    if (_status == ContentStatus.published ||
        _status == ContentStatus.archived) {
      return [
        FilledButton.icon(
          icon: const Icon(Icons.edit_note),
          label: const Text('建立替代草稿'),
          onPressed: _busy
              ? null
              : () => _run(() async {
                    await wf.createDraftFromPublished(type, _ymd,
                        editorEmail: email);
                    if (mounted) Navigator.pop(context);
                  }),
        ),
        if (_status == ContentStatus.published) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            icon: const Icon(Icons.archive_outlined),
            label: const Text('撤下（學生立即讀不到）'),
            onPressed: _busy
                ? null
                : () => _run(() async {
                      await wf.archive(type, _ymd, email);
                      if (mounted) Navigator.pop(context);
                    }),
          ),
        ],
      ];
    }
    if (_status == ContentStatus.review) {
      return [
        FilledButton.icon(
          icon: const Icon(Icons.publish),
          label: const Text('發布'),
          onPressed: _busy
              ? null
              : () => _run(() async {
                    final ok = await _confirmPublish();
                    if (ok != true) return;
                    await wf.approveAndPublish(type, _ymd,
                        publisherEmail: email);
                    if (mounted) Navigator.pop(context);
                  }),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.undo),
          // A9：Review→Rejected 是「退回修改」（Rejected 為正式 status，可再改回 Draft）。
          label: const Text('退回修改'),
          onPressed: _busy
              ? null
              : () => _run(() async {
                    await wf.reject(type, _ymd, email);
                    if (mounted) Navigator.pop(context);
                  }),
        ),
      ];
    }
    return [
      if (_status == ContentStatus.rejected)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('此版本已退回修改，可編輯後重新送審。',
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      FilledButton.icon(
        icon: const Icon(Icons.save_outlined),
        label: const Text('儲存草稿'),
        onPressed: _busy ? null : () => _run(() => _saveDraft(wf, email, snack: true)),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        icon: const Icon(Icons.rate_review_outlined),
        label: const Text('送出審核'),
        onPressed: _busy
            ? null
            : () => _run(() async {
                  await _saveDraft(wf, email);
                  final ok = await _confirmSubmit();
                  if (ok != true) return;
                  await wf.submitForReview(type, _ymd, email);
                  if (mounted) Navigator.pop(context);
                }),
      ),
    ];
  }

  /// A7 送審前 summary。
  Future<bool?> _confirmSubmit() => showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('送出審核'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('日期：$_ymd'),
              Text('經文：${_ref.text.trim()}'),
              if (_title.text.trim().isNotEmpty) Text('標題：${_title.text.trim()}'),
              const SizedBox(height: 8),
              const Text('審核通過並發布後，只會在指定日期顯示於學生首頁。'),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('送出審核')),
          ],
        ),
      );

  /// A10 發布前最終確認。
  Future<bool?> _confirmPublish() => showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('確認發布'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('發布日期：$_ymd'),
              Text('經文：${_ref.text.trim()}'),
              const SizedBox(height: 8),
              Text('此版本將成為正式 Published 每日經文。學生首頁只有在 $_ymd 才會顯示。'),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('確認發布')),
          ],
        ),
      );

  Future<void> _saveDraft(dynamic wf, String email, {bool snack = false}) async {
    final books = ref.read(booksProvider).value ?? const [];
    final parsed = VerseLocator.parse(_ref.text.trim(), books);
    if (parsed == null || parsed.verse == null) {
      throw '無法解析經文節位（請輸入例如「約3:16」的單節）';
    }
    await wf.saveDraft(
      AdminDailyVerseScreen._type,
      _ymd,
      contentType: 'daily_verse',
      payload: {
        'date': _ymd,
        'book_id': parsed.bookId,
        'chapter': parsed.chapter,
        'verse': parsed.verse,
        'ref_text': _ref.text.trim(),
        'title': _title.text.trim(),
        'content': _content.text.trim(),
      },
      editorEmail: email,
    );
    ref.invalidate(adminDailyVerseListProvider);
    if (snack && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('草稿已儲存')));
    }
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
