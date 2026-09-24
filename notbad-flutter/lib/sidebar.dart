import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'theme.dart';

const _kWritingExtensions = {'.md', '.markdown', '.txt', '.text'};
const _kRowHeight = 28.0;

/// File sidebar: a tree of the writing files around the current document.
/// Keyboard-driven (↑/↓ browse, →/← open and close, Enter opens, n for new file, Esc returns to editor)
/// and watches the folder so external changes appear automatically.
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
  Map<String, String> _gitStatus = {};
  StreamSubscription<FileSystemEvent>? _watch;
  Timer? _watchDebounce;

  @override
  void initState() {
    super.initState();
    _expanded.add(widget.rootPath);
    _startWatch();
    _refreshGitStatus();
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
      _refreshGitStatus();
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
          if (mounted) {
            setState(() {});
            _refreshGitStatus();
          }
        });
      });
    } catch (_) {
      // Watching unsupported here; the tree still refreshes on rebuild.
    }
  }

  Future<void> _refreshGitStatus() async {
    try {
      var dir = Directory(widget.rootPath);
      String? repoRoot;
      while (true) {
        if (Directory(p.join(dir.path, '.git')).existsSync()) {
          repoRoot = dir.path;
          break;
        }
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
      if (repoRoot == null) {
        if (_gitStatus.isNotEmpty && mounted) {
          setState(() => _gitStatus = {});
        }
        return;
      }

      final res = await Process.run('git', ['status', '--porcelain', '-uall'],
          workingDirectory: repoRoot);
      if (res.exitCode == 0 && mounted) {
        final map = <String, String>{};
        final lines = (res.stdout as String).split('\n');
        for (final line in lines) {
          if (line.length < 4) continue;
          final status = line.substring(0, 2).trim();
          var filePath = line.substring(3).trim();
          if (filePath.startsWith('"') && filePath.endsWith('"')) {
            filePath = filePath.substring(1, filePath.length - 1);
          }
          final absPath = p.normalize(p.join(repoRoot, filePath));
          map[absPath] = status;
        }
        setState(() => _gitStatus = map);
      }
    } catch (_) {
      // Git not available or not a git repository
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

  String get _currentContextDir {
    if (_rows.isNotEmpty && _highlight >= 0 && _highlight < _rows.length) {
      final entity = _rows[_highlight].$1;
      if (entity is Directory) return entity.path;
      return p.dirname(entity.path);
    }
    return widget.rootPath;
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
          final parent = entity == null ? null : p.dirname(entity.path);
          final idx = _rows.indexWhere((r) => r.$1.path == parent);
          if (idx != -1) setState(() => _highlight = idx);
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
        _activate(_highlight);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyN:
        _promptNewFile(_currentContextDir);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        widget.onExit?.call();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  Future<void> _promptNewFile(String targetDir) async {
    final controller = TextEditingController(text: 'untitled.md');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: widget.palette.bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: widget.palette.border),
        ),
        title: Text('New File',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: widget.palette.fg)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Folder: ${p.basename(targetDir)}',
              style: TextStyle(fontSize: 11.5, color: widget.palette.muted),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              style: TextStyle(fontSize: 13, color: widget.palette.fg),
              decoration: InputDecoration(
                labelText: 'File Name',
                labelStyle:
                    TextStyle(color: widget.palette.muted, fontSize: 12),
                hintText: 'e.g. notes.md',
                isDense: true,
                filled: true,
                fillColor: widget.palette.sidebarBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: widget.palette.border),
                ),
              ),
              onSubmitted: (val) => Navigator.pop(context, val.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: TextStyle(color: widget.palette.muted, fontSize: 12)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: widget.palette.accent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Create', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );

    if (result == null || result.isEmpty) return;
    var fileName = result;
    if (!p
        .extension(fileName)
        .toLowerCase()
        .contains(RegExp(r'\.(md|markdown|txt|text)$'))) {
      fileName = '$fileName.md';
    }
    final filePath = p.join(targetDir, fileName);
    final file = File(filePath);
    if (file.existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File "$fileName" already exists.')),
        );
      }
      return;
    }
    try {
      file.writeAsStringSync('');
      if (mounted) {
        setState(() {
          _expanded.add(targetDir);
        });
      }
      widget.onOpenFile(file.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating file: $e')),
        );
      }
    }
  }

  Future<void> _promptNewFolder(String targetDir) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: widget.palette.bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: widget.palette.border),
        ),
        title: Text('New Folder',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: widget.palette.fg)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Inside: ${p.basename(targetDir)}',
              style: TextStyle(fontSize: 11.5, color: widget.palette.muted),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              style: TextStyle(fontSize: 13, color: widget.palette.fg),
              decoration: InputDecoration(
                labelText: 'Folder Name',
                labelStyle:
                    TextStyle(color: widget.palette.muted, fontSize: 12),
                hintText: 'e.g. chapters',
                isDense: true,
                filled: true,
                fillColor: widget.palette.sidebarBg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: widget.palette.border),
                ),
              ),
              onSubmitted: (val) => Navigator.pop(context, val.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: TextStyle(color: widget.palette.muted, fontSize: 12)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: widget.palette.accent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Create', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );

    if (result == null || result.isEmpty) return;
    final dirPath = p.join(targetDir, result);
    final dir = Directory(dirPath);
    if (!dir.existsSync()) {
      try {
        dir.createSync(recursive: true);
        if (mounted) {
          setState(() {
            _expanded.add(targetDir);
            _expanded.add(dirPath);
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error creating folder: $e')),
          );
        }
      }
    }
  }

  Future<void> _revealInExplorer(String path) async {
    try {
      if (Platform.isWindows) {
        final target = FileSystemEntity.isDirectorySync(path)
            ? path
            : p.dirname(path);
        await Process.run('explorer.exe', [target]);
      } else if (Platform.isMacOS) {
        await Process.run('open', ['-R', path]);
      } else if (Platform.isLinux) {
        final target = FileSystemEntity.isDirectorySync(path)
            ? path
            : p.dirname(path);
        await Process.run('xdg-open', [target]);
      }
    } catch (_) {}
  }

  Future<void> _deleteEntity(FileSystemEntity entity) async {
    final isDir = entity is Directory;
    final name = p.basename(entity.path);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: widget.palette.bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: widget.palette.border),
        ),
        title: Text('Delete ${isDir ? "Folder" : "File"}?',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: widget.palette.fg)),
        content: Text('Are you sure you want to delete "$name"?',
            style: TextStyle(fontSize: 13, color: widget.palette.muted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: widget.palette.muted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        entity.deleteSync(recursive: isDir);
        if (mounted) setState(() {});
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not delete: $e')),
          );
        }
      }
    }
  }

  void _showContextMenu(
      BuildContext context, Offset position, FileSystemEntity? entity) {
    final isDir = entity is Directory;
    final targetDir = entity == null
        ? widget.rootPath
        : (isDir ? entity.path : p.dirname(entity.path));

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx + 1, position.dy + 1),
      color: widget.palette.toolbarBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: widget.palette.border),
      ),
      items: [
        PopupMenuItem(
          value: 'new_file',
          height: 32,
          child: Row(
            children: [
              Icon(Icons.note_add_outlined,
                  size: 14, color: widget.palette.muted),
              const SizedBox(width: 8),
              Text('New File…',
                  style: TextStyle(fontSize: 12.5, color: widget.palette.fg)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'new_folder',
          height: 32,
          child: Row(
            children: [
              Icon(Icons.create_new_folder_outlined,
                  size: 14, color: widget.palette.muted),
              const SizedBox(width: 8),
              Text('New Folder…',
                  style: TextStyle(fontSize: 12.5, color: widget.palette.fg)),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),
        PopupMenuItem(
          value: 'reveal',
          height: 32,
          child: Row(
            children: [
              Icon(Icons.folder_open_outlined,
                  size: 14, color: widget.palette.muted),
              const SizedBox(width: 8),
              Text(
                  Platform.isMacOS
                      ? 'Reveal in Finder'
                      : 'Reveal in File Explorer',
                  style: TextStyle(fontSize: 12.5, color: widget.palette.fg)),
            ],
          ),
        ),
        if (entity != null) ...[
          const PopupMenuDivider(height: 1),
          PopupMenuItem(
            value: 'delete',
            height: 32,
            child: const Row(
              children: [
                Icon(Icons.delete_outline, size: 14, color: Colors.redAccent),
                SizedBox(width: 8),
                Text('Delete',
                    style: TextStyle(fontSize: 12.5, color: Colors.redAccent)),
              ],
            ),
          ),
        ],
      ],
    ).then((value) {
      if (value == 'new_file') {
        _promptNewFile(targetDir);
      } else if (value == 'new_folder') {
        _promptNewFolder(targetDir);
      } else if (value == 'reveal') {
        _revealInExplorer(entity?.path ?? targetDir);
      } else if (value == 'delete' && entity != null) {
        _deleteEntity(entity);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final rows = <(FileSystemEntity, int)>[];
    _collectRows(widget.rootPath, 0, rows);
    _rows = rows;
    if (_highlight >= rows.length) {
      _highlight = rows.isEmpty ? 0 : rows.length - 1;
    }

    final rootDirName = p.basename(widget.rootPath);

    return Container(
      color: palette.sidebarBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sidebar Header with Folder title and Quick Actions
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 38, 6, 6),
            child: Row(
              children: [
                Expanded(
                  child: Tooltip(
                    message: widget.rootPath,
                    child: Text(
                      rootDirName.isEmpty ? 'WORKSPACE' : rootDirName.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: palette.muted,
                      ),
                    ),
                  ),
                ),
                // New File
                IconButton(
                  tooltip: 'New file (N)',
                  onPressed: () => _promptNewFile(widget.rootPath),
                  iconSize: 15,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.note_add_outlined,
                      color: palette.muted.withValues(alpha: 0.85)),
                ),
                // New Folder
                IconButton(
                  tooltip: 'New folder…',
                  onPressed: () => _promptNewFolder(widget.rootPath),
                  iconSize: 15,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.create_new_folder_outlined,
                      color: palette.muted.withValues(alpha: 0.85)),
                ),
                // Choose / Switch Folder
                IconButton(
                  tooltip: 'Open folder…',
                  onPressed: widget.onPickRoot,
                  iconSize: 15,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.folder_open_outlined,
                      color: palette.muted.withValues(alpha: 0.85)),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: palette.border.withValues(alpha: 0.6)),
          Expanded(
            child: GestureDetector(
              onSecondaryTapDown: (details) =>
                  _showContextMenu(context, details.globalPosition, null),
              child: rows.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.description_outlined,
                                size: 28,
                                color: palette.muted.withValues(alpha: 0.4)),
                            const SizedBox(height: 8),
                            Text(
                              'No writing files yet',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 12, color: palette.muted),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                side: BorderSide(color: palette.border),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                              ),
                              icon: Icon(Icons.add,
                                  size: 14, color: palette.accent),
                              label: Text('New File',
                                  style: TextStyle(
                                      fontSize: 12, color: palette.accent)),
                              onPressed: () =>
                                  _promptNewFile(widget.rootPath),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Focus(
                      focusNode: widget.focusNode,
                      onKeyEvent: _onKey,
                      child: ListView.builder(
                        controller: _scroll,
                        itemExtent: _kRowHeight,
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                        itemCount: rows.length,
                        itemBuilder: (context, i) {
                          final (entity, depth) = rows[i];
                          return _row(entity, depth, i);
                        },
                      ),
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

    return GestureDetector(
      onSecondaryTapDown: (details) =>
          _showContextMenu(context, details.globalPosition, entity),
      child: InkWell(
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
              if (!isDir &&
                  _gitStatus.containsKey(p.normalize(entity.path))) ...[
                const SizedBox(width: 4),
                _buildGitBadge(_gitStatus[p.normalize(entity.path)]!, palette),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGitBadge(String status, TracePalette palette) {
    final isUntracked = status.contains('?');
    final color =
        isUntracked ? const Color(0xFF1A7F37) : const Color(0xFFD4A72C);
    final label = isUntracked ? '+' : '•';
    return Padding(
      padding: const EdgeInsets.only(right: 4.0),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: isUntracked ? 13 : 16,
          fontWeight: FontWeight.bold,
          height: 1.0,
        ),
      ),
    );
  }
}
