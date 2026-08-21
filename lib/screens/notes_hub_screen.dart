import 'package:flutter/material.dart';

import 'bookmarks_screen.dart';
import 'sermon_notes_screen.dart';

/// 新版筆記中心：經文相關標記與證道筆記共用一個一級入口。
class NotesHubScreen extends StatelessWidget {
  const NotesHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('筆記'),
          bottom: const TabBar(tabs: [
            Tab(text: '經文筆記'),
            Tab(text: '證道筆記'),
          ]),
        ),
        body: const TabBarView(children: [
          _ScriptureNotesEntry(),
          _SermonNotesEntry(),
        ]),
      ),
    );
  }
}

class _ScriptureNotesEntry extends StatelessWidget {
  const _ScriptureNotesEntry();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('經文筆記與收藏', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('沿用既有資料，不搬移、不重建。你原本的書籤、螢光筆與筆記都會保留。', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.outline)),
        const SizedBox(height: 20),
        Card(
          child: ListTile(
            leading: const Icon(Icons.collections_bookmark_outlined),
            title: const Text('開啟我的標記'),
            subtitle: const Text('書籤、螢光筆、經文筆記'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BookmarksScreen(initialTab: 2))),
          ),
        ),
      ],
    );
  }
}

class _SermonNotesEntry extends StatelessWidget {
  const _SermonNotesEntry();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('證道筆記', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('主題、日期、經文、筆記、祂的話、實踐與感想；既有匯入／匯出能力繼續保留。', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.outline)),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SermonNotesScreen())),
          icon: const Icon(Icons.edit_note),
          label: const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Text('開啟證道筆記')),
        ),
      ],
    );
  }
}
