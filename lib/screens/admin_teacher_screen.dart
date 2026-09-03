import 'package:flutter/material.dart' hide Visibility;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/study_content.dart';
import '../models/teacher.dart';
import '../providers/providers.dart';
import 'admin_study_content_screen.dart' show StudyContentEditor;

/// Admin 老師專區：Books → Chapters → Add Teaching（＝建立 Study Content Draft）。
/// Book/Chapter 帶 audience（public/church/internal）；church 只從 Active Churches picker 選。
class AdminTeacherBooksScreen extends ConsumerWidget {
  const AdminTeacherBooksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminTeacherBooksProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('老師專區書卷')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('新增書卷'),
        onPressed: () => _editBook(context, ref, null),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('載入失敗：$e')),
        data: (books) => books.isEmpty
            ? const Center(
                child: Padding(
                    padding: EdgeInsets.all(32), child: Text('尚無書卷。右下角可新增。')))
            : ListView(
                children: [
                  for (final b in books)
                    ListTile(
                      leading: const Icon(Icons.menu_book_outlined),
                      title: Text(b.title.isEmpty ? b.id : b.title,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          '順序 ${b.order}｜${b.status.label}｜${b.audience?.label ?? '未設對象'}'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: '編輯書卷',
                          onPressed: () => _editBook(context, ref, b),
                        ),
                        const Icon(Icons.chevron_right),
                      ]),
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => AdminTeacherChaptersScreen(book: b))),
                    ),
                ],
              ),
      ),
    );
  }

  void _editBook(BuildContext context, WidgetRef ref, TeacherBook? b) {
    _bookOrChapterDialog(
      context: context,
      ref: ref,
      title: b == null ? '新增書卷' : '編輯書卷',
      initId: b?.id ?? '',
      initTitle: b?.title ?? '',
      initDesc: b?.description ?? '',
      initOrder: b?.order ?? 0,
      initStatus: b?.status ?? ContentStatus.draft,
      initAudience: b?.audience ?? Audience.internal,
      initChurches: b?.allowedChurchIds ?? const [],
      hasDesc: true,
      onSave: (id, title, desc, order, status, aud, churches) async {
        await ref.read(teacherRepositoryProvider).saveBook(TeacherBook(
              id: id,
              title: title,
              description: desc,
              order: order,
              status: status,
              audience: aud,
              allowedChurchIds: aud == Audience.church ? churches : const [],
            ));
        ref.invalidate(adminTeacherBooksProvider);
      },
    );
  }
}

class AdminTeacherChaptersScreen extends ConsumerWidget {
  final TeacherBook book;
  const AdminTeacherChaptersScreen({super.key, required this.book});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminTeacherChaptersProvider(book.id));
    return Scaffold(
      appBar: AppBar(title: Text('章：${book.title.isEmpty ? book.id : book.title}')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('新增章'),
        onPressed: () => _editChapter(context, ref, null),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('載入失敗：$e')),
        data: (chapters) => ListView(
          children: [
            for (final c in chapters)
              ExpansionTile(
                title: Text(c.title.isEmpty ? c.id : c.title,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                    '順序 ${c.order}｜${c.status.label}｜${c.audience?.label ?? '未設對象'}'),
                children: [
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('編輯章'),
                    onTap: () => _editChapter(context, ref, c),
                  ),
                  ListTile(
                    leading: const Icon(Icons.add_circle_outline),
                    title: const Text('新增教導內容'),
                    subtitle: const Text('建立一則 Study Content 草稿並掛在此章'),
                    onTap: () => _addTeaching(context, ref, c),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _editChapter(BuildContext context, WidgetRef ref, TeacherChapter? c) {
    _bookOrChapterDialog(
      context: context,
      ref: ref,
      title: c == null ? '新增章' : '編輯章',
      initId: c?.id ?? '',
      initTitle: c?.title ?? '',
      initDesc: '',
      initOrder: c?.order ?? 0,
      initStatus: c?.status ?? ContentStatus.draft,
      initAudience: c?.audience ?? Audience.internal,
      initChurches: c?.allowedChurchIds ?? const [],
      hasDesc: false,
      onSave: (id, title, _, order, status, aud, churches) async {
        await ref.read(teacherRepositoryProvider).saveChapter(TeacherChapter(
              id: id,
              bookId: book.id,
              title: title,
              order: order,
              status: status,
              audience: aud,
              allowedChurchIds: aud == Audience.church ? churches : const [],
            ));
        ref.invalidate(adminTeacherChaptersProvider(book.id));
      },
    );
  }

  /// **Add Teaching＝建立 Study Content Draft**（帶 teacherBookId/teacherChapterId），
  /// 走既有 Draft→Review→Published workflow；**不建 teacher_teachings CMS**。
  Future<void> _addTeaching(
      BuildContext context, WidgetRef ref, TeacherChapter c) async {
    final id = 'teach__n${DateTime.now().millisecondsSinceEpoch}';
    final draft = StudyContentItem(
      id: id,
      status: ContentStatus.draft,
      visibility: Visibility.internal,
      audience: Audience.internal,
      contentType: StudyContentType.topicArticle,
      teacherBookId: book.id,
      teacherChapterId: c.id,
      provenance: const ContentProvenance(source: 'native', note: 'teacher_teaching'),
    );
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => StudyContentEditor(item: draft, isNew: true)));
    ref.invalidate(adminTeacherChaptersProvider(book.id));
  }
}

typedef _SaveCb = Future<void> Function(String id, String title, String desc,
    int order, ContentStatus status, Audience audience, List<String> churches);

void _bookOrChapterDialog({
  required BuildContext context,
  required WidgetRef ref,
  required String title,
  required String initId,
  required String initTitle,
  required String initDesc,
  required int initOrder,
  required ContentStatus initStatus,
  required Audience initAudience,
  required List<String> initChurches,
  required bool hasDesc,
  required _SaveCb onSave,
}) {
  final id = TextEditingController(text: initId);
  final t = TextEditingController(text: initTitle);
  final desc = TextEditingController(text: initDesc);
  final order = TextEditingController(text: '$initOrder');
  var status = initStatus;
  var audience = initAudience;
  final churches = {...initChurches};
  final isNew = initId.isEmpty;

  showDialog<void>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setLocal) {
        final churchesAsync = ref.watch(adminAllChurchesProvider);
        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: id,
                  enabled: isNew,
                  decoration: const InputDecoration(
                      labelText: 'ID / slug（建立後不可改）', isDense: true)),
              TextField(
                  controller: t,
                  decoration:
                      const InputDecoration(labelText: '標題', isDense: true)),
              if (hasDesc)
                TextField(
                    controller: desc,
                    decoration:
                        const InputDecoration(labelText: '描述（選填）', isDense: true)),
              TextField(
                  controller: order,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: '排序（數字）', isDense: true)),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('狀態', style: Theme.of(context).textTheme.labelSmall),
              ),
              SegmentedButton<ContentStatus>(
                segments: const [
                  ButtonSegment(value: ContentStatus.draft, label: Text('草稿')),
                  ButtonSegment(
                      value: ContentStatus.published, label: Text('已發布')),
                ],
                selected: {
                  status == ContentStatus.published
                      ? ContentStatus.published
                      : ContentStatus.draft
                },
                onSelectionChanged: (s) => setLocal(() => status = s.first),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('對象（audience）',
                    style: Theme.of(context).textTheme.labelSmall),
              ),
              SegmentedButton<Audience>(
                segments: const [
                  ButtonSegment(value: Audience.public, label: Text('公開')),
                  ButtonSegment(value: Audience.church, label: Text('教會')),
                  ButtonSegment(value: Audience.internal, label: Text('內部')),
                ],
                selected: {audience},
                onSelectionChanged: (s) => setLocal(() => audience = s.first),
              ),
              if (audience == Audience.church)
                churchesAsync.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => Text('教會載入失敗：$e'),
                  data: (all) {
                    final active = all.where((c) => c.active).toList();
                    return Column(children: [
                      const SizedBox(height: 6),
                      if (active.isEmpty)
                        const Text('尚無 Active 教會。', style: TextStyle(fontSize: 12)),
                      Wrap(spacing: 6, children: [
                        for (final c in active)
                          FilterChip(
                            label: Text(c.name.isEmpty ? c.id : c.name),
                            selected: churches.contains(c.id),
                            onSelected: (sel) => setLocal(() => sel
                                ? churches.add(c.id)
                                : churches.remove(c.id)),
                          ),
                      ]),
                    ]);
                  },
                ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                final cid = id.text.trim();
                if (cid.isEmpty) return;
                if (audience == Audience.church && churches.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('教會對象需至少選一間 Active 教會。')));
                  return;
                }
                final nav = Navigator.of(context);
                await onSave(cid, t.text.trim(), desc.text.trim(),
                    int.tryParse(order.text.trim()) ?? 0, status, audience,
                    churches.toList());
                nav.pop();
              },
              child: const Text('儲存'),
            ),
          ],
        );
      },
    ),
  );
}
