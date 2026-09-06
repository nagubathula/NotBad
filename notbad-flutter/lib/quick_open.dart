import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'theme.dart';

const _kWritingExtensions = {'.md', '.markdown', '.txt', '.text'};
const _kMaxFiles = 500;
const _kMaxFileBytes = 512 * 1024;
const _kMaxResults = 40;

class QuickOpenResult {
  final String path;
  final int? lineNumber; // 1-based, for content matches
  final String? preview;
  final int? offset; // character offset of the match
  const QuickOpenResult(this.path,
      {this.lineNumber, this.preview, this.offset});
}

/// Trace's ⇧⌘O "Open Document": jump to any writing file near your document
/// by name — extended with full-text search across the same folder.
Future<void> showQuickOpen(
  BuildContext context,
  TracePalette palette,
  String rootPath,
  List<String> recentFiles,
  void Function(String path, int? offset) onOpen,
) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Quick open',
    barrierColor: Colors.black.withValues(alpha: 0.08),
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (context, _, _) => Align(
      alignment: const Alignment(0, -0.55),
      child: _QuickOpen(
        palette: palette,
        rootPath: rootPath,
        recentFiles: recentFiles,
        onOpen: onOpen,
      ),
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

class _QuickOpen extends StatefulWidget {
  final TracePalette palette;
  final String rootPath;
  final List<String> recentFiles;
  final void Function(String path, int? offset) onOpen;

  const _QuickOpen({
    required this.palette,
    required this.rootPath,
    required this.recentFiles,
    required this.onOpen,
  });

  @override
  State<_QuickOpen> createState() => _QuickOpenState();
}

class _QuickOpenState extends State<_QuickOpen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  var _selected = 0;
  var _searching = false;
  List<QuickOpenResult> _results = [];

  @override
  void initState() {
    super.initState();
    _results = [
      for (final r in widget.recentFiles.take(8))
        if (File(r).existsSync()) QuickOpenResult(r),
    ];
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  List<File> _allFiles() {
    final files = <File>[];
    void scan(Directory dir) {
      if (files.length >= _kMaxFiles) return;
      try {
        for (final e in dir.listSync()) {
          if (files.length >= _kMaxFiles) return;
          final name = p.basename(e.path);
          if (name.startsWith('.')) continue;
          if (e is Directory) {
            scan(e);
          } else if (e is File &&
              _kWritingExtensions.contains(p.extension(e.path).toLowerCase())) {
            files.add(e);
          }
        }
      } catch (_) {}
    }

    scan(Directory(widget.rootPath));
    return files;
  }

  Future<void> _search(String query) async {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      setState(() {
        _results = [
          for (final r in widget.recentFiles.take(8))
            if (File(r).existsSync()) QuickOpenResult(r),
        ];
        _selected = 0;
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    final nameMatches = <QuickOpenResult>[];
    final contentMatches = <QuickOpenResult>[];
    final files = _allFiles();
    for (final file in files) {
      if (nameMatches.length + contentMatches.length >= _kMaxResults) break;
      final base = p.basenameWithoutExtension(file.path).toLowerCase();
      if (base.contains(q)) {
        nameMatches.add(QuickOpenResult(file.path));
        continue;
      }
      try {
        if (file.lengthSync() > _kMaxFileBytes) continue;
        final text = file.readAsStringSync();
        final idx = text.toLowerCase().indexOf(q);
        if (idx != -1) {
          final lineNumber = '\n'.allMatches(text.substring(0, idx)).length + 1;
          final lineStart = text.lastIndexOf('\n', idx) + 1;
          var lineEnd = text.indexOf('\n', idx);
          if (lineEnd == -1) lineEnd = text.length;
          contentMatches.add(QuickOpenResult(
            file.path,
            lineNumber: lineNumber,
            preview: text.substring(lineStart, lineEnd).trim(),
            offset: idx,
          ));
        }
      } catch (_) {}
      // Yield to the UI between files.
      if (files.length > 50) await Future<void>.delayed(Duration.zero);
      if (!mounted || _controller.text.trim().toLowerCase() != q) return;
    }
    if (!mounted) return;
    setState(() {
      _results = [...nameMatches, ...contentMatches];
      _selected = 0;
      _searching = false;
    });
  }

  void _openSelected() {
    if (_results.isEmpty) return;
    final r = _results[_selected];
    Navigator.of(context).pop();
    widget.onOpen(r.path, r.offset);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        setState(() {
          if (_results.isNotEmpty) _selected = (_selected + 1) % _results.length;
        });
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        setState(() {
          if (_results.isNotEmpty) {
            _selected = (_selected - 1 + _results.length) % _results.length;
          }
        });
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
        _openSelected();
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
                  onChanged: (q) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 250),
                        () => _search(q));
                  },
                  style: TextStyle(color: palette.fg, fontSize: 16),
                  cursorColor: palette.accent,
                  decoration: InputDecoration(
                    hintText: 'Search files and their contents',
                    hintStyle: TextStyle(color: palette.muted, fontSize: 16),
                    border: InputBorder.none,
                    suffixIcon: _searching
                        ? Padding(
                            padding: const EdgeInsets.all(12),
                            child: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: palette.muted),
                            ),
                          )
                        : null,
                  ),
                ),
              ),
            ),
            Divider(height: 1, color: palette.border),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                itemCount: _results.length,
                itemBuilder: (context, i) => _row(_results[i], i),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(QuickOpenResult result, int i) {
    final palette = widget.palette;
    final isSelected = i == _selected;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        _selected = i;
        _openSelected();
      },
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? palette.fg.withValues(alpha: 0.07) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(
              result.lineNumber == null
                  ? Icons.description_outlined
                  : Icons.manage_search,
              size: 16,
              color: isSelected ? palette.accent : palette.muted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.basenameWithoutExtension(result.path) +
                        (result.lineNumber != null
                            ? '  ·  line ${result.lineNumber}'
                            : ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.fg, fontSize: 14),
                  ),
                  Text(
                    result.preview ?? result.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.muted, fontSize: 11.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
