import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'theme.dart';

const _kWritingExtensions = {'.md', '.markdown', '.txt', '.text'};
const _kRowHeight = 28.0;

/// File sidebar: a tree of the writing files around the current document,
/// like Trace's ⌘\ panel. Fully keyboard-driven (↑/↓ browse, →/← open and
/// close, Enter opens, Esc returns to the editor) and it watches the folder
/// so external changes appear automatically.
class FileSidebar extends StatefulWidget {
  final TracePalette palette;
  final String rootPath;
  final String? currentFile;
  final void Function(String path) onOpenFile;
  final VoidCallback onPickRoot;
  final FocusNode? focusNode;
  final VoidCallback? onExit;

  const FileSidebar({
    super.key,
    required this.palette,
    required this.rootPath,
    required this.currentFile,
    required this.onOpenFile,
    required this.onPickRoot,
    this.focusNode,
    this.onExit,
  });

  @override
  State<FileSidebar> createState() => _FileSidebarState();
}

class _FileSidebarState extends State<FileSidebar> {
  final Set<String> _expanded = {};
  final _scroll = ScrollController();
  var _highlight = 0;
  List<(FileSystemEntity, int)> _rows = const [];
  StreamSubscription<FileSystemEvent>? _watch;
  Timer? _watchDebounce;

  @override
  void initState() {
    super.initState();
    _expanded.add(widget.rootPath);
    _startWatch();
  }

  @override
  void didUpdateWidget(FileSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rootPath != widget.rootPath) {
      _expanded
        ..clear()
        ..add(widget.rootPath);
      _highlight = 0;
      _startWatch();
    }
  }

  @override
  void dispose() {
    _watch?.cancel();
    _watchDebounce?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _startWatch() {
    _watch?.cancel();
    try {
      _watch = Directory(widget.rootPath)
          .watch(recursive: true)
          .listen((_) {
        _watchDebounce?.cancel();
        _watchDebounce = Timer(const Duration(milliseconds: 300), () {
          if (mounted) setState(() {});
        });
      });
    } catch (_) {
      // Watching unsupported here; the tree still refreshes on rebuild.
    }
  }

  List<FileSystemEntity> _childrenOf(String dir) {
    try {
      final entries = Directory(dir).listSync().where((e) {
        final name = p.basename(e.path);
        if (name.startsWith('.')) return false;
        if (e is Directory) return true;
        return _kWritingExtensions.contains(p.extension(e.path).toLowerCase());
      }).toList();
      entries.sort((a, b) {
        final aDir = a is Directory, bDir = b is Directory;
        if (aDir != bDir) return aDir ? -1 : 1;
        return p
            .basename(a.path)
            .toLowerCase()
            .compareTo(p.basename(b.path).toLowerCase());
      });
      return entries;
    } catch (_) {
      return const [];
    }
  }

  void _collectRows(String dir, int depth, List<(FileSystemEntity, int)> rows) {
    for (final entity in _childrenOf(dir)) {
      rows.add((entity, depth));
      if (entity is Directory && _expanded.contains(entity.path)) {
        _collectRows(entity.path, depth + 1, rows);
      }
    }
  }

  void _moveHighlight(int delta) {
    if (_rows.isEmpty) return;
    setState(() {
      _highlight = (_highlight + delta).clamp(0, _rows.length - 1);
    });
    if (_scroll.hasClients) {
      final target = _highlight * _kRowHeight;
      final top = _scroll.offset;
      final bottom = top + _scroll.position.viewportDimension - _kRowHeight;
      if (target < top) {
        _scroll.jumpTo(target);
      } else if (target > bottom) {
        _scroll.jumpTo(target - _scroll.position.viewportDimension + _kRowHeight);
      }
    }
  }

  void _activate(int index, {bool collapseOnly = false, bool expandOnly = false}) {
    if (index < 0 || index >= _rows.length) return;
    final (entity, _) = _rows[index];
    if (entity is Directory) {
      setState(() {
        if (collapseOnly) {
          _expanded.remove(entity.path);
        } else if (expandOnly) {
          _expanded.add(entity.path);
        } else {
          _expanded.contains(entity.path)
              ? _expanded.remove(entity.path)
              : _expanded.add(entity.path);
        }
      });
    } else if (!collapseOnly) {
      widget.onOpenFile(entity.path);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _moveHighlight(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _moveHighlight(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _activate(_highlight, expandOnly: false);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        final (entity, depth) = _rows.isEmpty
            ? (null, 0)
            : (_rows[_highlight].$1, _rows[_highlight].$2);
        if (entity is Directory && _expanded.contains(entity.path)) {
          _activate(_highlight, collapseOnly: true);
        } else if (depth > 0) {
          // Jump to the parent folder row.
          final parent = entity == null ? null : p.dirname(entity.path);
          final idx = _rows.indexWhere((r) => r.$1.path == parent);
          if (idx != -1) setState(() => _highlight = idx);
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
        _activate(_highlight);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        widget.onExit?.call();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final rows = <(FileSystemEntity, int)>[];
    _collectRows(widget.rootPath, 0, rows);
    _rows = rows;
    if (_highlight >= rows.length) _highlight = rows.isEmpty ? 0 : rows.length - 1;

    return Container(
      color: palette.sidebarBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 38, 8, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Choose folder…',
                  onPressed: widget.onPickRoot,
                  iconSize: 15,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.create_new_folder_outlined,
                      color: palette.muted.withValues(alpha: 0.8)),
                ),
              ],
            ),
          ),
          Expanded(
            child: Focus(
              focusNode: widget.focusNode,
              onKeyEvent: _onKey,
              child: ListView.builder(
                controller: _scroll,
                itemExtent: _kRowHeight,
                padding: const EdgeInsets.fromLTRB(8, 2, 8, 12),
                itemCount: rows.length,
                itemBuilder: (context, i) {
                  final (entity, depth) = rows[i];
                  return _row(entity, depth, i);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(FileSystemEntity entity, int depth, int index) {
    final palette = widget.palette;
    final isDir = entity is Directory;
    final isCurrent = entity.path == widget.currentFile;
    final hasKeyFocus =
        widget.focusNode?.hasFocus == true && index == _highlight;
    final name = isDir
        ? p.basename(entity.path)
        : p.basenameWithoutExtension(entity.path);

    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () {
        setState(() => _highlight = index);
        _activate(index);
      },
      child: Container(
        decoration: BoxDecoration(
          color: isCurrent
              ? palette.fg.withValues(alpha: 0.09)
              : (hasKeyFocus ? palette.fg.withValues(alpha: 0.05) : null),
          borderRadius: BorderRadius.circular(6),
          border: hasKeyFocus
              ? Border.all(color: palette.accent.withValues(alpha: 0.45))
              : null,
        ),
        padding: EdgeInsets.only(left: 6.0 + depth * 14, right: 6),
        child: Row(
          children: [
            if (isDir) ...[
              Icon(
                _expanded.contains(entity.path)
                    ? Icons.keyboard_arrow_down
                    : Icons.keyboard_arrow_right,
                size: 14,
                color: palette.muted,
              ),
              const SizedBox(width: 3),
              Icon(Icons.folder_outlined, size: 13, color: palette.muted),
              const SizedBox(width: 6),
            ] else
              const SizedBox(width: 23),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: isDir
                      ? palette.muted
                      : (isCurrent
                          ? palette.fg
                          : palette.fg.withValues(alpha: 0.82)),
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
