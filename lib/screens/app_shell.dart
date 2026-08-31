import 'package:flutter/material.dart';

import 'bible_hub_screen.dart';
import 'my_content_screen.dart';
import 'reading_plans_screen.dart';
import 'student_home_screen.dart';
import 'me_screen.dart';

/// 新版學生端主殼：首頁／聖經／計畫／筆記／我的。
///
/// Reader 本身仍由既有 ChapterScreen 以獨立 route 推入，因此進入閱讀時
/// NavigationBar 會自然隱藏，返回時也會回到原本來源頁，保留正確 back stack。
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _pages = <Widget>[
    StudentHomeScreen(),
    BibleHubScreen(),
    ReadingPlansScreen(),
    MyContentScreen(),
    MeScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首頁',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: '聖經',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note),
            label: '計畫',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: '內容',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
