import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared selection state for personal-data lists.
class SelectionController<T> extends ChangeNotifier {
  final Set<T> _selected = <T>{};
  bool _active = false;

  bool get active => _active;
  Set<T> get selected => Set.unmodifiable(_selected);
  int get count => _selected.length;
  bool contains(T value) => _selected.contains(value);

  void start([T? initial]) {
    _active = true;
    if (initial != null) _selected.add(initial);
    notifyListeners();
  }

  void toggle(T value) {
    _active = true;
    if (!_selected.remove(value)) _selected.add(value);
    notifyListeners();
  }

  void selectAll(Iterable<T> values) {
    _active = true;
    _selected
      ..clear()
      ..addAll(values);
    notifyListeners();
  }

  void cancel() {
    _selected.clear();
    _active = false;
    notifyListeners();
  }
}

class StudentSelectionAppBar extends StatelessWidget implements PreferredSizeWidget {
  const StudentSelectionAppBar({
    super.key,
    required this.title,
    required this.selectionCount,
    required this.totalCount,
    required this.onCancel,
    required this.onSelectAll,
  });

  final String title;
  final int selectionCount;
  final int totalCount;
  final VoidCallback onCancel;
  final VoidCallback onSelectAll;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) => AppBar(
        leading: TextButton(onPressed: onCancel, child: const Text('取消')),
        leadingWidth: 72,
        title: Text(selectionCount == 0 ? title : '已選 $selectionCount 項'),
        actions: [
          TextButton(
            onPressed: totalCount == 0 ? null : onSelectAll,
            child: Text(selectionCount == totalCount && totalCount > 0 ? '取消全選' : '全選'),
          ),
        ],
      );
}

class StudentBatchAction {
  const StudentBatchAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool destructive;
}

class StudentBatchActionBar extends StatelessWidget {
  const StudentBatchActionBar({super.key, required this.actions});
  final List<StudentBatchAction> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Material(
        color: scheme.surface,
        elevation: 6,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final action in actions)
                Expanded(
                  child: TextButton.icon(
                    onPressed: action.onPressed,
                    icon: Icon(action.icon,
                        color: action.destructive ? scheme.error : null),
                    label: Text(action.label,
                        style: TextStyle(
                            color: action.destructive ? scheme.error : null)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Swipe row that never hard-deletes by gesture itself. The callback decides the
/// operation, then the row snaps back. iOS edge-back remains owned by the route;
/// row swipe begins from the row body and only wins after the row drag recognizer.
class StudentSwipeRow extends StatelessWidget {
  const StudentSwipeRow({
    super.key,
    required this.dismissKey,
    required this.child,
    this.onSwipeStartToEnd,
    this.onSwipeEndToStart,
    this.startLabel,
    this.endLabel,
    this.startIcon = Icons.copy_outlined,
    this.endIcon = Icons.delete_outline,
    this.endDestructive = true,
  });

  final Key dismissKey;
  final Widget child;
  final Future<void> Function()? onSwipeStartToEnd;
  final Future<void> Function()? onSwipeEndToStart;
  final String? startLabel;
  final String? endLabel;
  final IconData startIcon;
  final IconData endIcon;
  final bool endDestructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Dismissible(
      key: dismissKey,
      direction: onSwipeStartToEnd != null && onSwipeEndToStart != null
          ? DismissDirection.horizontal
          : onSwipeStartToEnd != null
              ? DismissDirection.startToEnd
              : DismissDirection.endToStart,
      dismissThresholds: const {
        DismissDirection.startToEnd: .42,
        DismissDirection.endToStart: .42,
      },
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          await onSwipeStartToEnd?.call();
        } else {
          await onSwipeEndToStart?.call();
        }
        return false;
      },
      background: _SwipeBackground(
        alignment: Alignment.centerLeft,
        icon: startIcon,
        label: startLabel ?? '',
        color: scheme.primaryContainer,
        foreground: scheme.onPrimaryContainer,
      ),
      secondaryBackground: _SwipeBackground(
        alignment: Alignment.centerRight,
        icon: endIcon,
        label: endLabel ?? '',
        color: endDestructive ? scheme.errorContainer : scheme.secondaryContainer,
        foreground: endDestructive ? scheme.onErrorContainer : scheme.onSecondaryContainer,
      ),
      child: child,
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.alignment,
    required this.icon,
    required this.label,
    required this.color,
    required this.foreground,
  });
  final Alignment alignment;
  final IconData icon;
  final String label;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
        alignment: alignment,
        color: color,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: foreground),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: foreground, fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      );
}

class StudentEmptyState extends StatelessWidget {
  const StudentEmptyState({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.actionLabel,
    this.onAction,
  });
  final String title;
  final String? subtitle;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 42, color: scheme.outline),
              const SizedBox(height: 12),
            ],
            Text(title, textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(subtitle!, textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.outline)),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class StudentErrorState extends StatelessWidget {
  const StudentErrorState({super.key, this.message = '暫時無法載入內容。', required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => StudentEmptyState(
        title: message,
        subtitle: '請稍後再試。',
        icon: Icons.cloud_off_outlined,
        actionLabel: '重試',
        onAction: onRetry,
      );
}

class StudentCompactLoading extends StatelessWidget {
  const StudentCompactLoading({super.key});
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4))),
      );
}

Future<void> copyHumanReadable(BuildContext context, String text,
    {String success = '已複製'}) async {
  await Clipboard.setData(ClipboardData(text: text.trim()));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(success), duration: const Duration(seconds: 1)),
  );
}

String joinHumanReadable(Iterable<String> entries) =>
    entries.map((e) => e.trim()).where((e) => e.isNotEmpty).join('\n\n———\n\n');
