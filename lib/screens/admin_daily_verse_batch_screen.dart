import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/daily_verse_batch.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../services/daily_verse_auto_selector.dart';
import '../services/daily_verse_scheduler.dart';

/// 每日經文「批次」後台。
///
/// 主流程（正式需求）＝**系統自動選取**：
///   自動產生（curated catalog＋corpus 正文，deterministic、已發布鎖定、fail-closed 留白）
///   → 預覽未來 30 天（節位＋corpus 正文＋排除/解析失敗/重複/書卷集中標示）
///   → 管理員移除／替換單筆 → 人工核准候選池 → 建立 Draft → 送 Review → Publish。
///
/// 進階流程（可選覆寫）＝手動輸入候選（保留舊行為，但不再是唯一方法）。
///
/// ⛔ 內容無關：經文正文一律來自正式 Bible corpus，程式不生成／改寫／補寫。
class AdminDailyVerseBatchScreen extends ConsumerStatefulWidget {
  const AdminDailyVerseBatchScreen({super.key});
  @override
  ConsumerState<AdminDailyVerseBatchScreen> createState() =>
      _AdminDailyVerseBatchScreenState();
}

class _AdminDailyVerseBatchScreenState
    extends ConsumerState<AdminDailyVerseBatchScreen> {
  final _manualEditor = TextEditingController();
  DailyVerseAutoPlan? _plan; // 自動選取計畫（in-memory，編輯即改這裡）
  bool _busy = false;
  bool _dirty = false; // 計畫已編輯、與已核准池不一致 → 需重新核准
  bool _showManual = false; // 進階手動覆寫

  @override
  void dispose() {
    _manualEditor.dispose();
    super.dispose();
  }

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
    final books = ref.watch(booksProvider).value ?? const <Book>[];
    final email = ref.watch(adminEmailProvider);
    final svc = ref.read(dailyVerseBatchServiceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('每日經文 · 批次排程')),
      body: poolAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('候選池載入失敗：$e')),
        data: (pool) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _poolStatus(pool),
            const SizedBox(height: 12),
            _autoActions(svc, books, pool),
            const SizedBox(height: 12),
            if (_plan != null) ...[
              _planSummary(_plan!, pool),
              const SizedBox(height: 8),
              ..._plan!.days.asMap().entries.map((e) =>
                  _dayTile(svc, books, e.key, e.value)),
              const SizedBox(height: 12),
              _workflowActions(svc, pool, email),
            ],
            const Divider(height: 32),
            _manualSection(svc, books, email),
          ],
        ),
      ),
    );
  }

  // ---- 候選池狀態 ----
  Widget _poolStatus(DailyVerseCandidatePool pool) => Card(
        child: ListTile(
          leading: Icon(pool.approved ? Icons.verified : Icons.edit_note,
              color: pool.approved ? Colors.green.shade700 : Colors.orange),
          title: Text('候選池 v${pool.version}｜${pool.candidates.length} 筆'
              '｜${pool.approved ? "已核准" : "未核准"}'
              '｜來源：${pool.source == "auto" ? "自動選取" : "手動輸入"}'),
          subtitle: Text([
            if (pool.source == 'auto')
              'catalog v${pool.catalogVersion}・algo v${pool.algoVersion}',
            _dirty ? '計畫已編輯，需重新核准' : (pool.isSchedulable ? '可排程' : '不可排程（需核准且非空）'),
          ].join('　·　')),
        ),
      );

  // ---- 自動選取動作 ----
  Widget _autoActions(dynamic svc, List<Book> books, DailyVerseCandidatePool pool) =>
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(
          icon: const Icon(Icons.auto_awesome),
          label: const Text('自動產生候選（未來30天）'),
          onPressed: _busy || books.isEmpty
              ? null
              : () => _run(() async {
                    final plan = await svc.generateAutoPlan(books: books, days: 30);
                    setState(() {
                      _plan = plan;
                      _dirty = true; // 尚未核准
                    });
                  }),
        ),
        if (_plan == null &&
            pool.source == 'auto' &&
            pool.candidates.any((c) => c.date != null))
          OutlinedButton.icon(
            icon: const Icon(Icons.history),
            label: const Text('載入先前產生的候選'),
            onPressed: _busy || books.isEmpty
                ? null
                : () => _run(() async {
                      final hist = await svc.loadPublishedHistory();
                      final plan = DailyVerseAutoSelector.planFromDatedPool(
                        books: books,
                        pool: pool,
                        publishedByDate: hist.publishedByDate,
                      );
                      setState(() {
                        _plan = plan;
                        _dirty = !pool.approved;
                      });
                    }),
          ),
      ]);

  // ---- 計畫摘要（排除/解析失敗/重複/書卷集中）----
  Widget _planSummary(DailyVerseAutoPlan plan, DailyVerseCandidatePool pool) {
    final draftable = plan.draftableDays.length;
    final published = plan.publishedDays.length;
    final failClosed = plan.failClosedDays.length;
    // 書卷集中：統計每書卷出現次數，>=4 天視為集中（建議性）。
    final byBook = <int, int>{};
    for (final d in plan.days) {
      if (d.bookId != null) byBook[d.bookId!] = (byBook[d.bookId!] ?? 0) + 1;
    }
    final concentrated = byBook.entries.where((e) => e.value >= 4).length;
    // 重複（防禦性；正常不應發生）。
    final keys = [
      for (final d in plan.days)
        if (d.bookId != null) '${d.bookId}:${d.chapter}:${d.verse}'
    ];
    final dup = keys.length != keys.toSet().length;
    final warn = failClosed > 0 || dup;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: warn
            ? Theme.of(context).colorScheme.errorContainer
            : Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text([
        '共 ${plan.days.length} 天',
        '可建立 $draftable',
        if (published > 0) '已發布鎖定 $published',
        if (failClosed > 0) '⚠️ 留白（無候選）$failClosed（不自動補位，請調整）',
        if (dup) '⚠️ 有重複節位',
        if (concentrated > 0) '書卷集中：$concentrated 卷 ≥4 天',
        if (plan.warnings.isNotEmpty) plan.warnings.join('／'),
        _dirty ? '尚未核准' : (pool.approved ? '已核准' : '未核准'),
      ].join('　·　'), style: const TextStyle(fontSize: 13)),
    );
  }

  Widget _dayTile(dynamic svc, List<Book> books, int index, DailyVersePlanDay d) {
    final cs = Theme.of(context).colorScheme;
    Widget trailing;
    if (d.published) {
      trailing = Icon(Icons.lock_outline, color: cs.outline);
    } else if (d.failClosed) {
      trailing = Icon(Icons.error_outline, color: cs.error);
    } else {
      trailing = Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
          tooltip: '替換',
          icon: const Icon(Icons.swap_horiz),
          onPressed: _busy ? null : () => _replaceDay(books, index, d),
        ),
        IconButton(
          tooltip: '移除（留白）',
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: _busy ? null : () => _removeDay(index, d),
        ),
      ]);
    }
    final subtitle = d.published
        ? '已發布・鎖定不覆寫：${d.resolvedText ?? ""}'
        : d.failClosed
            ? '留白（無合規候選，不 fabricate）'
            : d.resolvedText ?? '';
    return ListTile(
      dense: true,
      leading: Text(d.date.length >= 5 ? d.date.substring(5) : d.date),
      title: Row(children: [
        Flexible(child: Text(d.ref.isEmpty ? '—' : d.ref)),
        for (final f in d.flags) ...[
          const SizedBox(width: 6),
          _chip(f == 'pronoun_start' ? '代名詞開頭' : f, cs.tertiaryContainer),
        ],
      ]),
      subtitle: Text(subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: d.failClosed ? TextStyle(color: cs.error) : null),
      trailing: trailing,
    );
  }

  Widget _chip(String text, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: const TextStyle(fontSize: 11)),
      );

  void _removeDay(int index, DailyVersePlanDay d) {
    setState(() {
      _plan!.days[index] = DailyVersePlanDay(date: d.date, failClosed: true);
      _dirty = true;
    });
  }

  Future<void> _replaceDay(List<Book> books, int index, DailyVersePlanDay d) async {
    final ctrl = TextEditingController(text: d.ref);
    final ref = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('替換 ${d.date} 的經文'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: '節位（例：約3:16）', hintText: '由 corpus 解析，正文不可自行輸入'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('替換')),
        ],
      ),
    );
    if (ref == null || ref.isEmpty) return;
    final day = DailyVerseAutoSelector.dayFromRef(books, d.date, ref);
    if (day == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('無法解析此節位（corpus 找不到單節）。')));
      }
      return;
    }
    setState(() {
      _plan!.days[index] = day;
      _dirty = true;
    });
  }

  // ---- 核准 → Draft → Review → Publish ----
  Widget _workflowActions(
      dynamic svc, DailyVerseCandidatePool pool, String email) {
    final plan = _plan!;
    final canApprove = plan.draftableDays.isNotEmpty;
    final canDraft = pool.approved && !_dirty && plan.draftableDays.isNotEmpty;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      FilledButton.icon(
        icon: const Icon(Icons.verified_outlined),
        label: const Text('人工核准候選池'),
        onPressed: _busy || !canApprove
            ? null
            : () => _confirm(
                  '核准 ${plan.draftableDays.length} 筆候選？'
                  '${plan.hasFailClosed ? "（含 ${plan.failClosedDays.length} 天留白將略過）" : ""}',
                  () async {
                    await svc.saveAutoPlan(plan);
                    await svc.approvePool();
                    ref.invalidate(dailyVersePoolProvider);
                    setState(() => _dirty = false);
                  },
                ),
      ),
      OutlinedButton.icon(
        icon: const Icon(Icons.playlist_add),
        label: Text('建立 ${plan.draftableDays.length} 筆 Draft'),
        onPressed: _busy || !canDraft
            ? null
            : () => _confirm('建立 ${plan.draftableDays.length} 筆 Draft？', () async {
                  final specs = DailyVerseAutoSelector.planToSpecs(plan);
                  await svc.applyDraftBatch(specs, editorEmail: email);
                  ref.invalidate(adminDailyVerseListProvider);
                }),
      ),
      OutlinedButton.icon(
        icon: const Icon(Icons.rate_review_outlined),
        label: const Text('批次送 Review'),
        onPressed: _busy || !canDraft
            ? null
            : () => _confirm('把這批草稿送審？', () async {
                  final dates = [for (final s in plan.draftableDays) s.date];
                  await svc.submitBatchForReview(dates, editorEmail: email);
                  ref.invalidate(adminDailyVerseListProvider);
                }),
      ),
      OutlinedButton.icon(
        icon: const Icon(Icons.publish_outlined),
        label: const Text('批次 Publish'),
        onPressed: _busy || !canDraft
            ? null
            : () => _confirm('發佈這批每日經文？學生將於各指定日期讀到。', () async {
                  final dates = [for (final s in plan.draftableDays) s.date];
                  await svc.publishBatch(dates, publisherEmail: email);
                  ref.invalidate(adminDailyVerseListProvider);
                }),
      ),
    ]);
  }

  // ---- 進階：手動輸入覆寫（保留舊行為，非唯一方法）----
  Widget _manualSection(dynamic svc, List<Book> books, String email) {
    return ExpansionTile(
      initiallyExpanded: _showManual,
      onExpansionChanged: (v) => setState(() => _showManual = v),
      title: const Text('進階：手動輸入候選（覆寫）',
          style: TextStyle(fontWeight: FontWeight.w600)),
      childrenPadding: const EdgeInsets.all(8),
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text('每行：ref | 標題 | 內文（標題/內文選填，由你親撰）。'
              '手動候選依池序逐日指派（不自動跳過已發布日期）。',
              style: TextStyle(fontSize: 12)),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _manualEditor,
          maxLines: 6,
          decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '約3:16 | 神的愛 | …\n詩23:1 | 耶和華是我的牧者 |'),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.save_outlined),
            label: const Text('儲存手動候選（重置核准）'),
            onPressed: _busy
                ? null
                : () => _run(() async {
                      await svc.saveCandidates(_parseManual(_manualEditor.text));
                      ref.invalidate(dailyVersePoolProvider);
                      setState(() => _plan = null);
                    }),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.event_note),
            label: const Text('由手動候選排程並預覽'),
            onPressed: _busy || books.isEmpty
                ? null
                : () => _run(() async {
                      final pool = await svc.loadPool();
                      final sched = DailyVerseScheduler.scheduleDays(pool,
                          startYmd: DailyVerseScheduler.addDaysYmd(
                              _todayTaipei(), 1),
                          days: 30);
                      if (!sched.ok) {
                        throw StateError(sched.failClosedReason == 'pool_not_approved'
                            ? '候選池尚未核准'
                            : '候選池為空');
                      }
                      final specs =
                          DailyVerseScheduler.buildDraftSpecs(sched, books);
                      setState(() {
                        _plan = DailyVerseAutoPlan(
                          startYmd: specs.isEmpty ? '' : specs.first.date,
                          requestedDays: specs.length,
                          days: [
                            for (final s in specs)
                              DailyVersePlanDay(
                                date: s.date,
                                ref: s.ref,
                                bookId: s.bookId,
                                chapter: s.chapter,
                                verse: s.verse,
                                resolvedText: s.resolvedText,
                                failClosed: !s.refResolves,
                              )
                          ],
                        );
                        _dirty = !pool.approved;
                      });
                    }),
          ),
        ]),
      ],
    );
  }

  String _todayTaipei() {
    // 與 date_key.taipeiTodayYmd 同義，避免額外 import 於 UI 層。
    final t = DateTime.now().toUtc().add(const Duration(hours: 8));
    return '${t.year.toString().padLeft(4, '0')}-'
        '${t.month.toString().padLeft(2, '0')}-'
        '${t.day.toString().padLeft(2, '0')}';
  }

  List<DailyVerseCandidate> _parseManual(String text) => [
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

  void _confirm(String msg, Future<void> Function() action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('確認'),
        content: Text(msg),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('確定')),
        ],
      ),
    );
    if (ok == true) {
      await _run(() async {
        await action();
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('完成')));
        }
      });
    }
  }
}
