import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../services/app_links.dart';
import '../services/verse_locator.dart';

class ScriptureReferenceValue {
  const ScriptureReferenceValue({
    required this.bookId,
    required this.chapter,
    required this.startVerse,
    this.endVerse,
  });

  final int bookId;
  final int chapter;
  final int startVerse;
  final int? endVerse;

  String label(List<Book> books) {
    final book = books[bookId - 1];
    if (endVerse != null && endVerse != startVerse) {
      return '${book.name} $chapter:$startVerse–$endVerse';
    }
    return '${book.name} $chapter:$startVerse';
  }

  String legacyAnchor() => 'b${bookId}_c${chapter}_v$startVerse';
}

/// Parses one verse or a continuous range. Never guesses invalid book/chapter/verse.
ScriptureReferenceValue? parseScriptureReference(
    String input, List<Book> books) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;
  final range = RegExp(r'^(.*?)(?:\s*[-–—]\s*(\d{1,3}))$').firstMatch(trimmed);
  final startText = range?.group(1)?.trim() ?? trimmed;
  final loc = VerseLocator.parse(startText, books);
  if (loc == null || loc.verse == null) return null;
  final start = loc.verse!;
  if (range == null) {
    return ScriptureReferenceValue(
        bookId: loc.bookId, chapter: loc.chapter, startVerse: start);
  }
  final end = int.tryParse(range.group(2)!);
  if (end == null || end < start) return null;
  final maxVerse = books[loc.bookId - 1].chapters[loc.chapter - 1].length;
  if (end > maxVerse) return null;
  return ScriptureReferenceValue(
      bookId: loc.bookId,
      chapter: loc.chapter,
      startVerse: start,
      endVerse: end);
}

ScriptureReferenceValue? parseLegacyScriptureRef(
    String value, List<Book> books) {
  final m = RegExp(r'^b(\d+)_c(\d+)_v(\d+)$').firstMatch(value.trim());
  if (m == null) return parseScriptureReference(value, books);
  final bookId = int.tryParse(m.group(1)!);
  final chapter = int.tryParse(m.group(2)!);
  final verse = int.tryParse(m.group(3)!);
  if (bookId == null || chapter == null || verse == null) return null;
  if (bookId < 1 || bookId > books.length) return null;
  final book = books[bookId - 1];
  if (chapter < 1 || chapter > book.chapterCount) return null;
  if (verse < 1 || verse > book.chapters[chapter - 1].length) return null;
  return ScriptureReferenceValue(
      bookId: bookId, chapter: chapter, startVerse: verse);
}

class ScriptureReferenceField extends ConsumerStatefulWidget {
  const ScriptureReferenceField({
    super.key,
    required this.values,
    required this.onChanged,
    this.title = '對應經文',
    this.serializeAsLegacyAnchor = false,
  });

  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final String title;
  final bool serializeAsLegacyAnchor;

  @override
  ConsumerState<ScriptureReferenceField> createState() =>
      _ScriptureReferenceFieldState();
}

class _ScriptureReferenceFieldState
    extends ConsumerState<ScriptureReferenceField> {
  final _manual = TextEditingController();
  String? _validation;

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  String _serialize(ScriptureReferenceValue refValue, List<Book> books) =>
      widget.serializeAsLegacyAnchor
          ? refValue.legacyAnchor()
          : refValue.label(books);

  void _add(ScriptureReferenceValue value, List<Book> books) {
    final serialized = _serialize(value, books);
    if (widget.values.contains(serialized)) return;
    widget.onChanged([...widget.values, serialized]);
  }

  Future<void> _addManual(List<Book> books) async {
    final value = parseScriptureReference(_manual.text, books);
    if (value == null) {
      setState(() => _validation = '無法辨識這個經文位置，請檢查書卷、章與節。');
      return;
    }
    setState(() => _validation = null);
    _add(value, books);
    _manual.clear();
  }

  @override
  Widget build(BuildContext context) {
    final booksAsync = ref.watch(booksProvider);
    return booksAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (books) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          if (widget.values.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final raw in widget.values)
                  _ReferenceChip(
                    raw: raw,
                    books: books,
                    onOpen: () {
                      final parsed = parseLegacyScriptureRef(raw, books);
                      if (parsed == null) return;
                      AppLinks.openVerseRef(
                          context, ref, parsed.label(books));
                    },
                    onRemove: () => widget.onChanged(
                        widget.values.where((e) => e != raw).toList()),
                  ),
              ],
            ),
          if (widget.values.isNotEmpty) const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _manual,
                  decoration: InputDecoration(
                    hintText: '輸入經文，例如 約翰福音 3:16',
                    errorText: _validation,
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _addManual(books),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: '加入經文',
                onPressed: () => _addManual(books),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('選取經文'),
              onPressed: () async {
                final picked = await showScripturePicker(context, books);
                if (picked != null) _add(picked, books);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ReferenceChip extends StatelessWidget {
  const _ReferenceChip({
    required this.raw,
    required this.books,
    required this.onOpen,
    required this.onRemove,
  });

  final String raw;
  final List<Book> books;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final parsed = parseLegacyScriptureRef(raw, books);
    final label = parsed?.label(books) ?? raw;
    return InputChip(
      avatar: const Icon(Icons.menu_book_outlined, size: 18),
      label: Text(label),
      onPressed: parsed == null ? null : onOpen,
      onDeleted: onRemove,
      deleteIcon: const Icon(Icons.close, size: 18),
    );
  }
}

Future<ScriptureReferenceValue?> showScripturePicker(
    BuildContext context, List<Book> books) {
  return showModalBottomSheet<ScriptureReferenceValue>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ScripturePickerSheet(books: books),
  );
}

class _ScripturePickerSheet extends StatefulWidget {
  const _ScripturePickerSheet({required this.books});
  final List<Book> books;

  @override
  State<_ScripturePickerSheet> createState() => _ScripturePickerSheetState();
}

class _ScripturePickerSheetState extends State<_ScripturePickerSheet> {
  int? _bookId;
  int? _chapter;
  int? _startVerse;
  int? _endVerse;

  @override
  Widget build(BuildContext context) {
    final book = _bookId == null ? null : widget.books[_bookId! - 1];
    final verseCount = book == null || _chapter == null
        ? 0
        : book.chapters[_chapter! - 1].length;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .78,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text('選取經文',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                TextButton(
                  onPressed: _bookId != null &&
                          _chapter != null &&
                          _startVerse != null
                      ? () => Navigator.pop(
                            context,
                            ScriptureReferenceValue(
                              bookId: _bookId!,
                              chapter: _chapter!,
                              startVerse: _startVerse!,
                              endVerse: _endVerse,
                            ),
                          )
                      : null,
                  child: const Text('加入'),
                ),
              ],
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _bookId == null
                  ? _BookStep(
                      books: widget.books,
                      onSelect: (id) => setState(() {
                        _bookId = id;
                        _chapter = null;
                        _startVerse = null;
                        _endVerse = null;
                      }),
                    )
                  : _chapter == null
                      ? _NumberStep(
                          key: const ValueKey('chapter'),
                          title: '${book!.name} · 選章',
                          count: book.chapterCount,
                          onBack: () => setState(() => _bookId = null),
                          onSelect: (value) => setState(() {
                            _chapter = value;
                            _startVerse = null;
                            _endVerse = null;
                          }),
                        )
                      : _VerseStep(
                          key: const ValueKey('verse'),
                          title: '${book!.name} $_chapter · 選節',
                          count: verseCount,
                          start: _startVerse,
                          end: _endVerse,
                          onBack: () => setState(() => _chapter = null),
                          onSelect: (value) => setState(() {
                            if (_startVerse == null) {
                              _startVerse = value;
                              _endVerse = null;
                            } else if (value < _startVerse!) {
                              _startVerse = value;
                              _endVerse = null;
                            } else if (value == _startVerse) {
                              _endVerse = null;
                            } else {
                              _endVerse = value;
                            }
                          }),
                        ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BookStep extends StatelessWidget {
  const _BookStep({required this.books, required this.onSelect});
  final List<Book> books;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => ListView(
        key: const ValueKey('books'),
        children: [
          for (final testament in ['ot', 'nt']) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
              child: Text(testament == 'ot' ? '舊約' : '新約',
                  style: Theme.of(context).textTheme.labelLarge),
            ),
            for (final book in books.where((b) => b.testament == testament))
              ListTile(
                title: Text(book.name),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onSelect(book.id),
              ),
          ],
        ],
      );
}

class _NumberStep extends StatelessWidget {
  const _NumberStep({
    super.key,
    required this.title,
    required this.count,
    required this.onBack,
    required this.onSelect,
  });
  final String title;
  final int count;
  final VoidCallback onBack;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          ListTile(
            leading: IconButton(
                onPressed: onBack, icon: const Icon(Icons.arrow_back)),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: count,
              itemBuilder: (_, i) => InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onSelect(i + 1),
                child: Center(child: Text('${i + 1}')),
              ),
            ),
          ),
        ],
      );
}

class _VerseStep extends StatelessWidget {
  const _VerseStep({
    super.key,
    required this.title,
    required this.count,
    required this.start,
    required this.end,
    required this.onBack,
    required this.onSelect,
  });
  final String title;
  final int count;
  final int? start;
  final int? end;
  final VoidCallback onBack;
  final ValueChanged<int> onSelect;

  bool selected(int value) {
    if (start == null) return false;
    final last = end ?? start!;
    return value >= start! && value <= last;
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          ListTile(
            leading: IconButton(
                onPressed: onBack, icon: const Icon(Icons.arrow_back)),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(start == null
                ? '點一下選起始節，再點較後的節可形成連續範圍。'
                : end == null
                    ? '已選第 $start 節；可再點一節形成範圍。'
                    : '已選第 $start–$end 節'),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: count,
              itemBuilder: (_, i) {
                final value = i + 1;
                final isSelected = selected(value);
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => onSelect(value),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$value'),
                  ),
                );
              },
            ),
          ),
        ],
      );
}
