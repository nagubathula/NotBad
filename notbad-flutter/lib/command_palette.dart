import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// A single searchable action. Trace renders these as plain rows:
/// title, a gray category label, and the shortcut on the right — no icons.
class PaletteAction {
  final String title;
  final String category;
  final String? subtitle;
  final String? shortcut;
  final bool checked;

  /// Hidden while browsing (empty query) but still found by fuzzy search —
  /// keeps the default list short without losing "type dark to go dark".
  final bool searchOnly;

  /// Small color dot rendered before the title (accent pickers).
  final Color? swatch;

  final VoidCallback run;

  const PaletteAction({
    required this.title,
    required this.category,
    required this.run,
    this.subtitle,
    this.shortcut,
    this.checked = false,
    this.searchOnly = false,
    this.swatch,
  });
}

Future<void> showCommandPalette(
  BuildContext context,
  TracePalette palette,
  List<PaletteAction> actions,
) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Command palette',
    barrierColor: Colors.black.withValues(alpha: 0.08),
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (context, _, _) => Align(
      alignment: const Alignment(0, -0.55),
      child: _CommandPalette(palette: palette, actions: actions),
    ),
    transitionBuilder: (context, animation, _, child) {
      final curved =
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween(begin: 0.97, end: 1.0).animate(curved),
          alignment: const Alignment(0, -0.55),
          child: child,
        ),
      );
    },
  );
}

class _CommandPalette extends StatefulWidget {
  final TracePalette palette;
  final List<PaletteAction> actions;
  const _CommandPalette({required this.palette, required this.actions});

  @override
  State<_CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<_CommandPalette> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  var _selected = 0;
  late List<PaletteAction> _filtered = _fuzzyFilter(widget.actions, '');

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _filter(String query) {
    setState(() {
      _filtered = _fuzzyFilter(widget.actions, query);
      _selected = 0;
    });
  }

  void _runSelected() {
    if (_filtered.isEmpty) return;
    final action = _filtered[_selected];
    Navigator.of(context).pop();
    action.run();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        setState(() {
          if (_filtered.isNotEmpty) {
            _selected = (_selected + 1) % _filtered.length;
          }
        });
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        setState(() {
          if (_filtered.isNotEmpty) {
            _selected = (_selected - 1 + _filtered.length) % _filtered.length;
          }
        });
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
        _runSelected();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final fieldBg = palette.brightness == Brightness.light
        ? const Color(0xFFFDFDFC)
        : const Color(0xFF353535);
    return Material(
      color: fieldBg,
      elevation: 16,
      shadowColor: Colors.black.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: 580,
        constraints: const BoxConstraints(maxHeight: 430),
        decoration: BoxDecoration(
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              child: Focus(
                onKeyEvent: _onKey,
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  onChanged: _filter,
                  style: TextStyle(color: palette.fg, fontSize: 16),
                  cursorColor: palette.accent,
                  decoration: InputDecoration(
                    hintText: 'Type a command or file name',
                    hintStyle: TextStyle(color: palette.muted, fontSize: 16),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
            Divider(height: 1, color: palette.border),
            Flexible(
              child: ListView.builder(
                controller: _scroll,
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                itemCount: _filtered.length,
                itemBuilder: (context, i) => _row(_filtered[i], i),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(PaletteAction action, int i) {
    final palette = widget.palette;
    final isSelected = i == _selected;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        _selected = i;
        _runSelected();
      },
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? palette.fg.withValues(alpha: 0.07) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            if (action.checked) ...[
              Icon(Icons.check, size: 15, color: palette.fg),
              const SizedBox(width: 6),
            ],
            if (action.swatch != null) ...[
              Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  color: action.swatch,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(action.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.fg, fontSize: 14.5)),
                  if (action.subtitle != null)
                    Text(action.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(color: palette.muted, fontSize: 11.5)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(action.category,
                style: TextStyle(color: palette.muted, fontSize: 12.5)),
            const Spacer(),
            if (action.shortcut != null)
              Text(action.shortcut!,
                  style: TextStyle(color: palette.muted, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }
}

/// Subsequence fuzzy matching with a simple score: earlier and consecutive
/// matches rank higher.
List<PaletteAction> _fuzzyFilter(List<PaletteAction> actions, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return [for (final a in actions) if (!a.searchOnly) a];
  final scored = <(int, PaletteAction)>[];
  for (final action in actions) {
    final score = _fuzzyScore(action.title.toLowerCase(), q) ??
        (action.subtitle == null
            ? null
            : _fuzzyScore(action.subtitle!.toLowerCase(), q));
    if (score != null) scored.add((score, action));
  }
  scored.sort((a, b) => b.$1.compareTo(a.$1));
  return [for (final s in scored) s.$2];
}

int? _fuzzyScore(String haystack, String needle) {
  var score = 0;
  var hIndex = 0;
  var lastMatch = -2;
  for (var n = 0; n < needle.length; n++) {
    final found = haystack.indexOf(needle[n], hIndex);
    if (found == -1) return null;
    score += 10;
    if (found == lastMatch + 1) score += 8; // consecutive
    if (found == 0) score += 12; // start of string
    score -= (found - hIndex).clamp(0, 10); // gap penalty
    lastMatch = found;
    hIndex = found + 1;
  }
  return score;
}
