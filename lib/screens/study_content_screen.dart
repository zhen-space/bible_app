import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/study_content.dart';
import '../providers/providers.dart';
import '../services/app_links.dart';

/// 學生「研讀內容」——**正式資料來源＝study_content（published+student）**，
/// 絕不 fallback knowledge/data；沒有就顯示正常空狀態。
///
/// 型別對學生的友善中文名稱（不改 wire enum）。
String studyTypeLabel(StudyContentType? t) => switch (t) {
      StudyContentType.parallel => '平行經文',
      StudyContentType.type => '預表／對應',
      StudyContentType.timeline => '時間軸',
      StudyContentType.person => '人物',
      StudyContentType.topicArticle => '主題研讀',
      null => '研讀內容',
    };

class StudentStudyContentScreen extends ConsumerWidget {
  const StudentStudyContentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // **authorization-aware**：public ∪ active-church（無 legacy visibility universe）。
    final async = ref.watch(authorizedStudyContentProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('研讀內容')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _StudyEmpty('研讀內容載入失敗，請稍後再試。'),
        data: (items) {
          if (items.isEmpty) {
            return const _StudyEmpty('目前尚無已發布的研讀內容。');
          }
          // 依型別分組呈現。
          final byType = <StudyContentType?, List<StudyContentItem>>{};
          for (final it in items) {
            (byType[it.contentType] ??= []).add(it);
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
            children: [
              ListTile(
                leading: const Icon(Icons.category_outlined),
                title: const Text('主題',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('依主題探索研讀內容'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const StudentTopicsScreen())),
              ),
              const Divider(),
              for (final entry in byType.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                  child: Text(studyTypeLabel(entry.key),
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                for (final it in entry.value) _itemTile(context, it),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _itemTile(BuildContext context, StudyContentItem it) => Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: ListTile(
          title: Text(it.title.isEmpty ? '(未命名)' : it.title,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (it.audience == Audience.church) churchBadge(context),
              if (it.body.isNotEmpty)
                Text(it.body, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => StudentStudyContentDetail(item: it))),
        ),
      );
}

/// 「教會專屬」標記（**不暴露 allowedChurchIds raw values**）。
Widget churchBadge(BuildContext context) => Container(
      margin: const EdgeInsets.only(top: 2, bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('教會專屬',
          style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.w600)),
    );

/// 研讀內容詳情：依型別呈現正式 typed payload（authority＝StudyContentItem）。
class StudentStudyContentDetail extends ConsumerWidget {
  final StudyContentItem item;
  const StudentStudyContentDetail({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved =
        ref.watch(savedStudyContentIdsProvider).value?.contains(item.id) ??
            false;
    return Scaffold(
      appBar: AppBar(
        title: Text(studyTypeLabel(item.contentType)),
        actions: [
          IconButton(
            icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
            tooltip: saved ? '取消儲存' : '儲存',
            onPressed: () async {
              final uid = ref.read(authUserProvider).value?.uid;
              if (uid == null) return;
              final repo = ref.read(savedStudyContentRepositoryProvider);
              saved
                  ? await repo.unsave(uid, item.id)
                  : await repo.save(uid, item.id);
              ref.invalidate(savedStudyContentIdsProvider);
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (item.audience == Audience.church) ...[
            churchBadge(context),
            const SizedBox(height: 8),
          ],
          Text(item.title,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          if (item.body.isNotEmpty)
            Text(item.body, style: const TextStyle(height: 1.7)),
          const SizedBox(height: 8),
          ..._typed(context, ref),
          if (item.scriptureRefs.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('相關經文', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            _refChips(context, ref, item.scriptureRefs),
          ],
        ],
      ),
    );
  }

  List<Widget> _typed(BuildContext context, WidgetRef ref) {
    final d = item.data;
    List<String> strs(Object? v) =>
        ((v as List?) ?? const []).map((e) => e.toString()).toList();
    switch (item.contentType) {
      case StudyContentType.parallel:
        final refs = strs(d['refs']);
        return refs.isEmpty
            ? []
            : [
                const SizedBox(height: 8),
                Text('平行經文', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 6),
                _refChips(context, ref, refs),
              ];
      case StudyContentType.type:
        return [
          if ((d['otRef'] ?? '').toString().isNotEmpty)
            _kv(context, ref, '舊約預表', d['otRef'].toString(), isRef: true),
          if ((d['ntRef'] ?? '').toString().isNotEmpty)
            _kv(context, ref, '新約應驗', d['ntRef'].toString(), isRef: true),
        ];
      case StudyContentType.timeline:
        return [
          if ((d['era'] ?? '').toString().isNotEmpty)
            _kv(context, ref, '分期', d['era'].toString()),
          if ((d['when'] ?? '').toString().isNotEmpty)
            _kv(context, ref, '年代', d['when'].toString()),
          if ((d['ref'] ?? '').toString().isNotEmpty)
            _kv(context, ref, '相關經文', d['ref'].toString(), isRef: true),
        ];
      case StudyContentType.person:
        final aka = strs(d['aka']);
        final events = (d['events'] as List?) ?? const [];
        return [
          if (aka.isNotEmpty) _kv(context, ref, '別名', aka.join('、')),
          if (events.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('重大事件', style: Theme.of(context).textTheme.labelLarge),
            for (final e in events)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text((e as Map)['title']?.toString() ?? ''),
                trailing: (e['ref']?.toString() ?? '').isEmpty
                    ? null
                    : TextButton(
                        onPressed: () => AppLinks.openVerseRef(
                            context, ref, e['ref'].toString()),
                        child: Text(e['ref'].toString())),
              ),
          ],
        ];
      case StudyContentType.topicArticle:
      case null:
        return [];
    }
  }

  Widget _kv(BuildContext context, WidgetRef ref, String k, String v,
          {bool isRef = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 72,
              child: Text(k,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(
            child: isRef
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: ActionChip(
                      avatar: const Icon(Icons.menu_book, size: 16),
                      label: Text(v),
                      onPressed: () => AppLinks.openVerseRef(context, ref, v),
                    ),
                  )
                : Text(v),
          ),
        ]),
      );

  Widget _refChips(BuildContext context, WidgetRef ref, List<String> refs) =>
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final r in refs)
            ActionChip(
              avatar: const Icon(Icons.menu_book, size: 16),
              label: Text(r),
              onPressed: () => AppLinks.openVerseRef(context, ref, r),
            ),
        ],
      );
}

/// 學生「主題」——正式 study_topics（published+student），依 sortOrder。
class StudentTopicsScreen extends ConsumerWidget {
  const StudentTopicsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(authorizedTopicsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('主題')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _StudyEmpty('主題載入失敗，請稍後再試。'),
        data: (topics) => topics.isEmpty
            ? const _StudyEmpty('目前尚無已發布的主題。')
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  for (final t in topics)
                    Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        title: Text(t.title.isEmpty ? t.id : t.title,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: t.description.isEmpty
                            ? null
                            : Text(t.description,
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    StudentTopicContentScreen(topic: t))),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// 主題 → 該主題的研讀內容（只回 published+student；query＋rules 兩層）。
class StudentTopicContentScreen extends ConsumerWidget {
  final StudyTopic topic;
  const StudentTopicContentScreen({super.key, required this.topic});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(authorizedStudyContentByTopicProvider(topic.id));
    return Scaffold(
      appBar: AppBar(title: Text(topic.title.isEmpty ? '主題' : topic.title)),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _StudyEmpty('載入失敗，請稍後再試。'),
        data: (items) => items.isEmpty
            ? const _StudyEmpty('此主題目前尚無已發布的研讀內容。')
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  if (topic.description.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(topic.description,
                          style: Theme.of(context).textTheme.bodyMedium),
                    ),
                  for (final it in items)
                    Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: Text(studyTypeLabel(it.contentType),
                            style: Theme.of(context).textTheme.labelSmall),
                        title: Text(it.title.isEmpty ? '(未命名)' : it.title,
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    StudentStudyContentDetail(item: it))),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// 已儲存的研讀內容：relationship 保留，開啟走 live authorized resolve。
/// revoked/未授權 → 顯示「目前無法存取」＋可移除；**不從 cache 顯示全文**。
class SavedStudyContentScreen extends ConsumerWidget {
  const SavedStudyContentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(resolvedSavedStudyContentProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('已儲存的研讀內容')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _StudyEmpty('載入失敗，請稍後再試。'),
        data: (rows) => rows.isEmpty
            ? const _StudyEmpty('尚未儲存任何研讀內容。')
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  for (final r in rows)
                    Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        title: Text(
                            r.item?.title.isNotEmpty == true
                                ? r.item!.title
                                : (r.item == null ? '（此內容）' : '(未命名)'),
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: r.item == null
                            ? Text(r.online ? '目前無法存取' : '目前無法驗證教會存取權',
                                style: const TextStyle(
                                    fontStyle: FontStyle.italic))
                            : (r.item!.audience == Audience.church
                                ? churchBadge(context)
                                : null),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (r.item != null) const Icon(Icons.chevron_right),
                          IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: '從已儲存移除',
                            onPressed: () async {
                              final uid = ref.read(authUserProvider).value?.uid;
                              if (uid == null) return;
                              await ref
                                  .read(savedStudyContentRepositoryProvider)
                                  .unsave(uid, r.id);
                              ref.invalidate(savedStudyContentIdsProvider);
                              ref.invalidate(resolvedSavedStudyContentProvider);
                            },
                          ),
                        ]),
                        onTap: r.item == null
                            ? () => ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(r.online
                                        ? '你目前沒有這項研讀內容的存取權。'
                                        : '目前無法驗證教會存取權，請確認連線後再試。')))
                            : () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => StudentStudyContentDetail(
                                        item: r.item!))),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _StudyEmpty extends StatelessWidget {
  final String message;
  const _StudyEmpty(this.message);

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu_book_outlined,
                  size: 40, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 12),
              Text(message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.outline)),
            ],
          ),
        ),
      );
}
