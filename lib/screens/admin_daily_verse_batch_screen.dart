import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/daily_verse_batch.dart';
import '../providers/providers.dart';
import '../services/daily_verse_scheduler.dart';
import '../utils/date_key.dart';

/// 每日經文「批次」後台：版本化候選池 → 人工核准 → 確定性排程未來 30 天 →
/// 批次預覽／逐句核對 → 批次建立 Draft → 批次送 Review → 批次 Publish。
///
/// ⛔ 內容無關：候選經文（ref／title／content）一律由管理者親自輸入，本畫面不 fabricate。
/// 正文只由 corpus 依 ref 解析顯示。未核准／空池 → fail-closed，不排程、不補位。
class AdminDailyVerseBatchScreen extends ConsumerStatefulWidget {
  const AdminDailyVerseBatchScreen({super.key});
  @override
  ConsumerState<AdminDailyVerseBatchScreen> createState() =>
      _AdminDailyVerseBatchScreenState();
}

class _AdminDailyVerseBatchScreenState
    extends ConsumerState<AdminDailyVerseBatchScreen> {
  final _editor = TextEditingController();
  late String _startYmd;
  bool _busy = false;
  bool _prefilled = false;

  @override
  void initState() {
    super.initState();
    _startYmd = DailyVerseScheduler.addDaysYmd(taipeiTodayYmd(), 1); // 預設明天起
  }

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  /// 文字 → 候選：每行 `ref | title | content`（title/content 選填）。
  List<DailyVerseCandidate> _parse(String text) => [
        for (final raw in text.split('\n'))
          if (raw.trim().isNotEmpty)
            () {
              final parts = raw.split('|').map((e) => e.trim()).toList();
              return DailyVerseCandidate(
                ref: parts[0],
                title: parts.length > 1 ? parts[1] : '',
                content: parts.length > 2 ? parts.sublist(2).join(' | ') : '',
              );
            }()
      ];

  String _toText(List<DailyVerseCandidate> cs) => cs
      .map((c) => [c.ref, c.title, c.content]
          .where((s) => s.isNotEmpty || c.title.isNotEmpty)
          .join(' | '))
      .join('\n');

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('失敗：$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final poolAsync = ref.watch(dailyVersePoolProvider);
    final books = ref.watch(booksProvider).value ?? const [];
    final email = ref.watch(adminEmailProvider);
    final svc = ref.read(dailyVerseBatchServiceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('每日經文 · 批次排程')),
      body: poolAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('候選池載入失敗：$e')),
        data: (pool) {
          if (!_prefilled) {
            _editor.text = _toText(pool.candidates);
            _prefilled = true;
          }
          final schedule = DailyVerseScheduler.scheduleDays(pool,
              startYmd: _startYmd, days: 30);
          final specs = DailyVerseScheduler.buildDraftSpecs(schedule, books);
          final v = DailyVerseScheduler.validate(specs);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _poolStatus(pool),
              const SizedBox(height: 12),
              const Text('候選清單（每行：ref | 標題 | 內文；標題/內文選填，由你親撰）',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextField(
                controller: _editor,
                maxLines: 8,
                decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '約3:16 | 神的愛 | …\n詩23:1 | 耶和華是我的牧者 |'),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('儲存候選（重置核准）'),
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                            await svc.saveCandidates(_parse(_editor.text));
                            ref.invalidate(dailyVersePoolProvider);
                          }),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.verified_outlined),
                  label: const Text('人工核准候選池'),
                  onPressed: _busy || pool.candidates.isEmpty
                      ? null
                      : () => _run(() async {
                            await svc.approvePool();
                            ref.invalidate(dailyVersePoolProvider);
                          }),
                ),
              ]),
              const Divider(height: 28),
              Row(children: [
                const Text('排程起始日：', style: TextStyle(fontWeight: FontWeight.w600)),
                Text(_startYmd),
                const Spacer(),
                const Text('未來 30 天'),
              ]),
              const SizedBox(height: 8),
              if (!schedule.ok)
                _banner(
                  schedule.failClosedReason == 'pool_not_approved'
                      ? '候選池尚未人工核准 → 不排程（fail-closed）。請先核准。'
                      : '候選池為空 → 不排程、不從整本聖經補位（fail-closed）。請先建立候選。',
                  Theme.of(context).colorScheme.errorContainer,
                )
              else ...[
                _validationSummary(v, schedule),
                const SizedBox(height: 8),
                ...specs.map(_previewTile),
                const SizedBox(height: 12),
                _batchActions(svc, specs, v, email),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _poolStatus(DailyVerseCandidatePool pool) => Card(
        child: ListTile(
          leading: Icon(pool.approved ? Icons.verified : Icons.edit_note,
              color: pool.approved ? Colors.green.shade700 : Colors.orange),
          title: Text('候選池 v${pool.version}｜${pool.candidates.length} 筆'
              '｜${pool.approved ? "已核准" : "未核准"}'),
          subtitle: Text(pool.isSchedulable ? '可排程' : '不可排程（需核准且非空）'),
        ),
      );

  Widget _validationSummary(
          DailyVerseBatchValidation v, DailyVerseScheduleResult s) =>
      _banner(
        [
          '排程 ${v.count} 天',
          if (s.warnings.any((w) => w.startsWith('shortfall:')))
            '候選不足：${s.warnings.firstWhere((w) => w.startsWith("shortfall:")).split(":")[1]} 天未排（請補候選，不自動補位）',
          if (!v.allResolve) '⚠️ ${v.unresolvedDates.length} 筆 ref 無法解析（見下方紅字，需修正）',
          if (v.hasDuplicateDates) '⚠️ 日期重複',
          if (v.canSubmit) '✓ 可批次建立',
        ].join('｜'),
        v.canSubmit
            ? Theme.of(context).colorScheme.secondaryContainer
            : Theme.of(context).colorScheme.errorContainer,
      );

  Widget _previewTile(DailyVerseDraftSpec s) => ListTile(
        dense: true,
        leading: Text(s.date.substring(5)), // MM-DD
        title: Text('${s.ref}${s.title.isEmpty ? "" : "　· ${s.title}"}'),
        subtitle: s.refResolves
            ? Text(s.resolvedText ?? '', maxLines: 2, overflow: TextOverflow.ellipsis)
            : Text('無法解析此節位（請修正候選）',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
        trailing: Icon(
          s.refResolves ? Icons.check_circle_outline : Icons.error_outline,
          color: s.refResolves
              ? Colors.green.shade700
              : Theme.of(context).colorScheme.error,
        ),
      );

  Widget _batchActions(dynamic svc, List<DailyVerseDraftSpec> specs,
          DailyVerseBatchValidation v, String email) =>
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(
          icon: const Icon(Icons.playlist_add),
          label: Text('建立 ${v.count} 筆 Draft'),
          onPressed: _busy || !v.canSubmit
              ? null
              : () => _confirmRun('建立 ${v.count} 筆 Draft？',
                  () => svc.applyDraftBatch(specs, editorEmail: email)),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.rate_review_outlined),
          label: const Text('批次送 Review'),
          onPressed: _busy || !v.canSubmit
              ? null
              : () => _confirmRun('把這批草稿送審？',
                  () => svc.submitBatchForReview(
                      [for (final s in specs) s.date],
                      editorEmail: email)),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.publish_outlined),
          label: const Text('批次 Publish'),
          onPressed: _busy || !v.canSubmit
              ? null
              : () => _confirmRun('發佈這批每日經文？學生將於各指定日期讀到。',
                  () => svc.publishBatch([for (final s in specs) s.date],
                      publisherEmail: email)),
        ),
      ]);

  void _confirmRun(String msg, Future<dynamic> Function() action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('確認'),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('確定')),
        ],
      ),
    );
    if (ok == true) {
      await _run(() async {
        await action();
        ref.invalidate(adminDailyVerseListProvider);
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('批次完成')));
        }
      });
    }
  }

  Widget _banner(String text, Color bg) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: const TextStyle(fontSize: 13)),
      );
}
