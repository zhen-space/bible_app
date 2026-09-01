import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/managed_content.dart';
import '../providers/providers.dart';
import '../services/verse_locator.dart';
import 'admin_study_content_screen.dart' show statusBadge;

/// 每日經文後台。workflow：Draft→Review→Published（+Rejected/Archived），
/// 沿用 ContentWorkflowService，型別 'daily_verses'、**contentId = 日期（YYYY-MM-DD）**。
/// doc id＝日期 ⇒ **每個日期至多一筆對外版本（one active per date 為結構不變量）**；
/// 要換內容＝從現行版本「建立替代草稿」→審核→發布（版本 +1、舊版入 versions）。
/// 學生端只在 date==today 且 published 顯示；未來日期先發布不會提前出現（fail-closed）。
class AdminDailyVerseScreen extends ConsumerWidget {
  const AdminDailyVerseScreen({super.key});

  static const _type = 'daily_verses';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(adminDailyVerseListProvider);
    final todayYmd = _ymd(DateTime.now());
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
        data: (rows) => rows.isEmpty
            ? const Center(
                child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('尚無每日經文。右下角可新增。')))
            : ListView.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final r = rows[i];
                  final date = r['_date'] as String;
                  final status = ContentStatus.fromName(r['status'] as String?);
                  final when = date.compareTo(todayYmd) == 0
                      ? '今天'
                      : (date.compareTo(todayYmd) > 0 ? '未來' : '過去');
                  return ListTile(
                    title: Text('$date · $when',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(spacing: 6, runSpacing: 4, children: [
                        statusBadge(context, status),
                        Text(_scriptureText(r)),
                      ]),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openEditor(context, ref, r),
                  );
                },
              ),
      ),
    );
  }

  static String _scriptureText(Map<String, dynamic> r) {
    final b = r['book_id'], c = r['chapter'], v = r['verse'];
    if (b == null) return '(未設定經文)';
    return '書$b $c:$v';
  }

  void _openEditor(
      BuildContext context, WidgetRef ref, Map<String, dynamic>? row) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DailyVerseEditor(row: row)),
    ).then((_) => ref.invalidate(adminDailyVerseListProvider));
  }

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
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
    _date = d != null ? DateTime.parse(d) : DateTime.now();
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
        const SizedBox(height: 20),
        ..._actions(),
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
                    await wf.approveAndPublish(type, _ymd,
                        publisherEmail: email);
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
                    await wf.reject(type, _ymd, email);
                    if (mounted) Navigator.pop(context);
                  }),
        ),
      ];
    }
    return [
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
                  await wf.submitForReview(type, _ymd, email);
                  if (mounted) Navigator.pop(context);
                }),
      ),
    ];
  }

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
