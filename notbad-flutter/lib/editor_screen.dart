import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import 'command_palette.dart';
import 'markdown_controller.dart';
import 'quick_open.dart';
import 'settings.dart';
import 'sidebar.dart';
import 'theme.dart';
import 'widgets/find_replace_bar.dart';
import 'widgets/floating_toolbar.dart';
import 'widgets/hover_toc.dart';
import 'widgets/window_title_bar.dart';

const kAppVersion = '1.1.0';
const kUpdateRepo = 'nagubathula/NotBad';

/// Hook the single-instance server uses to hand a file path (or an empty
/// string, meaning "just focus") to the running editor.
void Function(String path)? onExternalOpen;

const _kFileTypes = XTypeGroup(
  label: 'Markdown',
  extensions: ['md', 'markdown', 'txt', 'text'],
);
const _kWritingExtensions = {'.md', '.markdown', '.txt', '.text'};

const _kTitleBarHeight = 36.0;

final _kWordRe = RegExp(r"[\p{L}\p{N}'’\-]+", unicode: true);

class EditorScreen extends StatefulWidget {
  final AppSettings settings;
  final String? initialFile;
  const EditorScreen({super.key, required this.settings, this.initialFile});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> with WindowListener {
  late MarkdownEditingController _controller;
  final _editorFocus = FocusNode();
  final _sidebarFocus = FocusNode();
  final _scroll = ScrollController();

  String? _path;
  String _savedText = '';
  String _lastText = '';
  String _lineEnding = '\n';
  var _dirty = false;
  var _wordCount = 0;
  var _selWordCount = 0;
  var _sidebarVisible = false;
  var _toolbarVisible = true;
  var _isMaximized = false;

  // Find & replace state.
  final _findController = TextEditingController();
  final _replaceController = TextEditingController();
  final _findFocus = FocusNode();
  var _findVisible = false;
  var _replaceVisible = false;
  var _matchIndex = -1;

  Timer? _autosaveTimer;
  DateTime? _fileMtime;
  File? _draftFile;
  var _editorWidth = 700.0;
  var _welcomeDismissed = false;
  var _externalDialogOpen = false;

  bool get _isTest => Platform.environment.containsKey('FLUTTER_TEST');

  TracePalette get _palette =>
      TracePalette.of(Theme.of(context).brightness, widget.settings.accent);

  @override
  void initState() {
    super.initState();
    _controller = MarkdownEditingController(
        palette: TracePalette.of(Brightness.light, widget.settings.accent));
    _controller.viewMode = MarkdownViewMode.values.firstWhere(
      (m) => m.name == widget.settings.viewMode,
      orElse: () => MarkdownViewMode.concealed,
    );
    _controller.addListener(_onTextChanged);
    _updateWindowTitle();
    _initWindow();
    // Diagnostic key logging, enabled only via NOTBAD_KEYLOG=<file path>.
    final keylog = Platform.environment['NOTBAD_KEYLOG'];
    if (keylog != null) {
      HardwareKeyboard.instance.addHandler((event) {
        try {
          File(keylog).writeAsStringSync(
            '${event.runtimeType} logical=${event.logicalKey.debugName} '
            'physical=${event.physicalKey.debugName} '
            'synth=${event.synthesized} '
            'ctrl=${HardwareKeyboard.instance.isControlPressed}\n',
            mode: FileMode.append,
          );
        } catch (_) {}
        return false;
      });
    }
    onExternalOpen = _handleExternalOpen;
    _autosaveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (widget.settings.autosave && _dirty && _path != null) _save();
      _stashDraft();
      _checkExternalChange();
    });
    if (widget.initialFile != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _restoreSession());
    }
    _initDraft();
    _checkForUpdates();
  }

  void _handleExternalOpen(String path) async {
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {}
    if (path.isNotEmpty && File(path).existsSync()) {
      _openPath(path);
    }
  }

  // ---- Untitled draft protection -----------------------------------------

  /// Untitled text is continuously stashed so a crash never loses it.
  Future<void> _initDraft() async {
    if (_isTest) return;
    try {
      final dir = await getApplicationSupportDirectory();
      _draftFile = File(p.join(dir.path, 'draft.md'));
      if (widget.initialFile == null &&
          _draftFile!.existsSync() &&
          _controller.text.isEmpty) {
        final draft = await _draftFile!.readAsString();
        if (draft.trim().isNotEmpty && mounted) {
          setState(() {
            _controller.value = TextEditingValue(
              text: draft.replaceAll('\r\n', '\n'),
              selection: TextSelection.collapsed(offset: draft.length),
            );
            _lastText = _controller.text;
            _dirty = true;
            _welcomeDismissed = true;
          });
          _updateWindowTitle();
        }
      }
    } catch (_) {}
  }

  void _stashDraft() {
    if (_draftFile == null) return;
    try {
      if (_path == null && _controller.text.trim().isNotEmpty) {
        _draftFile!.writeAsStringSync(_controller.text);
      } else if (_draftFile!.existsSync()) {
        _draftFile!.deleteSync();
      }
    } catch (_) {}
  }

  // ---- External change detection -----------------------------------------

  DateTime? _mtimeOf(String path) {
    try {
      return File(path).lastModifiedSync();
    } catch (_) {
      return null;
    }
  }

  /// If the open file changed on disk (another app, sync, git), reload it —
  /// silently when we have no local edits, with a choice when we do.
  Future<void> _checkExternalChange() async {
    if (_path == null || _externalDialogOpen) return;
    final mtime = _mtimeOf(_path!);
    if (mtime == null || _fileMtime == null || !mtime.isAfter(_fileMtime!)) {
      return;
    }
    String raw;
    try {
      raw = await File(_path!).readAsString();
    } catch (_) {
      return;
    }
    final text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    _fileMtime = mtime;
    if (text == _controller.text) return;

    if (!_dirty) {
      final caret = _controller.selection.isValid
          ? _controller.selection.start.clamp(0, text.length)
          : 0;
      setState(() {
        _savedText = text;
        _lastText = text;
        _controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: caret),
        );
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: const Duration(seconds: 2),
            content: Text('$_docName changed on disk — reloaded')));
      }
      return;
    }

    if (!mounted) return;
    _externalDialogOpen = true;
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('“$_docName” changed on disk'),
        content: const Text(
            'The file was modified outside NotBad while you have unsaved '
            'changes here.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, 'keep'),
              child: const Text('Keep My Version')),
          FilledButton(
              onPressed: () => Navigator.pop(context, 'reload'),
              child: const Text('Reload From Disk')),
        ],
      ),
    );
    _externalDialogOpen = false;
    if (choice == 'reload') {
      setState(() {
        _savedText = text;
        _lastText = text;
        _dirty = false;
        _controller.value = TextEditingValue(
          text: text,
          selection: const TextSelection.collapsed(offset: 0),
        );
      });
      _updateWindowTitle();
    }
    // "Keep": _fileMtime already advanced, so the next save wins quietly.
  }

  // ---- Update check ------------------------------------------------------

  Future<void> _checkForUpdates() async {
    if (_isTest) return;
    final today = DateTime.now().difference(DateTime(2020)).inDays;
    if (widget.settings.lastUpdateCheckDay == today) return;
    widget.settings.setLastUpdateCheckDay(today);
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      final request = await client.getUrl(
          Uri.parse('https://api.github.com/repos/$kUpdateRepo/releases/latest'));
      request.headers.set('Accept', 'application/vnd.github+json');
      final response = await request.close();
      if (response.statusCode != 200) return;
      final body = await response.transform(utf8.decoder).join();
      final tag = (jsonDecode(body) as Map<String, dynamic>)['tag_name']
          as String?;
      if (tag == null) return;
      final latest = tag.replaceFirst(RegExp('^v'), '');
      if (latest != kAppVersion && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 6),
          content: Text('NotBad $latest is available'),
          action: SnackBarAction(
            label: 'View',
            onPressed: () => _openLink(
                'https://github.com/$kUpdateRepo/releases/latest'),
          ),
        ));
      }
    } catch (_) {
      // Offline or no releases yet — stay quiet.
    }
  }

  Future<void> _restoreSession() async {
    final path = widget.initialFile!;
    await _openPath(path, confirm: false);
    if (_path == path && widget.settings.lastFile == path) {
      final caret =
          widget.settings.lastCaret.clamp(0, _controller.text.length);
      _controller.selection = TextSelection.collapsed(offset: caret);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToOffset(caret);
      });
    }
  }

  Future<void> _initWindow() async {
    try {
      windowManager.addListener(this);
      await windowManager.setPreventClose(true);
      _isMaximized = await windowManager.isMaximized();
    } catch (_) {
      // Window management unavailable (tests); ignore.
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.palette = _palette;
  }

  @override
  void dispose() {
    if (onExternalOpen == _handleExternalOpen) onExternalOpen = null;
    try {
      windowManager.removeListener(this);
    } catch (_) {}
    _autosaveTimer?.cancel();
    _controller.dispose();
    _editorFocus.dispose();
    _sidebarFocus.dispose();
    _findController.dispose();
    _replaceController.dispose();
    _findFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ---- Window events -----------------------------------------------------

  @override
  void onWindowClose() async {
    if (await _confirmDiscard()) {
      await widget.settings.setSession(
          _path, _controller.selection.isValid ? _controller.selection.start : 0);
      try {
        await windowManager.destroy();
      } catch (_) {}
    }
  }

  @override
  void onWindowBlur() {
    if (widget.settings.autosave && _dirty && _path != null) _save();
    _stashDraft();
  }

  @override
  void onWindowFocus() {
    _checkExternalChange();
  }

  @override
  void onWindowMaximize() => setState(() => _isMaximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _isMaximized = false);

  Future<void> _toggleMaximize() async {
    try {
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
    } catch (_) {}
  }

  void _onTextChanged() {
    final textChanged = _controller.text != _lastText;
    if (textChanged) {
      _lastText = _controller.text;
      // The toolbar recedes while you type and returns on mouse movement.
      if (_toolbarVisible) setState(() => _toolbarVisible = false);
      if (_findVisible) _updateMatches();
      _typewriterScroll();
      if (!_welcomeDismissed && _controller.text.isNotEmpty) {
        setState(() => _welcomeDismissed = true);
      }
    }
    final dirty = _controller.text != _savedText;
    final words = _kWordRe.allMatches(_controller.text).length;
    final sel = _controller.selection;
    final selWords = (sel.isValid && !sel.isCollapsed)
        ? _kWordRe.allMatches(sel.textInside(_controller.text)).length
        : 0;
    if (dirty != _dirty || words != _wordCount || selWords != _selWordCount) {
      setState(() {
        _dirty = dirty;
        _wordCount = words;
        _selWordCount = selWords;
      });
      _updateWindowTitle();
    }
  }

  // ---- Document commands -------------------------------------------------

  String get _docName => _path == null ? 'Untitled' : p.basename(_path!);

  Future<void> _updateWindowTitle() async {
    try {
      await windowManager.setTitle(_dirty ? '$_docName — Edited' : _docName);
    } catch (_) {}
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    if (widget.settings.autosave && _path != null) {
      await _save();
      return true;
    }
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Save changes to “$_docName”?'),
        content: const Text('Your changes will be lost otherwise.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, 'cancel'),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, 'discard'),
              child: const Text("Don't Save")),
          FilledButton(
              onPressed: () => Navigator.pop(context, 'save'),
              child: const Text('Save')),
        ],
      ),
    );
    if (result == 'save') {
      await _save();
      return !_dirty;
    }
    return result == 'discard';
  }

  Future<void> _newDocument() async {
    if (!await _confirmDiscard()) return;
    setState(() {
      _path = null;
      _savedText = '';
      _lastText = '';
      _controller.clear();
      _dirty = false;
    });
    _updateWindowTitle();
  }

  Future<void> _openDialog() async {
    if (!await _confirmDiscard()) return;
    final file = await openFile(acceptedTypeGroups: [_kFileTypes]);
    if (file != null) await _openPath(file.path, confirm: false);
  }

  Future<void> _openPath(String path, {bool confirm = true}) async {
    if (confirm && !await _confirmDiscard()) return;
    try {
      final raw = await File(path).readAsString();
      // The editor works in LF; remember the file's endings for saving.
      final text = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
      setState(() {
        _path = path;
        _lineEnding = raw.contains('\r\n') ? '\r\n' : '\n';
        _savedText = text;
        _lastText = text;
        _dirty = false;
        _controller.value = TextEditingValue(
          text: text,
          selection: const TextSelection.collapsed(offset: 0),
        );
        _toolbarVisible = true;
        _welcomeDismissed = true;
      });
      _fileMtime = _mtimeOf(path);
      widget.settings.addRecent(path);
      widget.settings.setSession(path, 0);
      _stashDraft();
      _editorFocus.requestFocus();
      _updateWindowTitle();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not open $path: $e')));
      }
    }
  }

  Future<void> _save() async {
    if (_path == null) return _saveAs();
    await File(_path!).writeAsString(_lineEnding == '\n'
        ? _controller.text
        : _controller.text.replaceAll('\n', _lineEnding));
    _fileMtime = _mtimeOf(_path!);
    _stashDraft();
    widget.settings.addRecent(_path!);
    widget.settings.setSession(
        _path, _controller.selection.isValid ? _controller.selection.start : 0);
    setState(() {
      _savedText = _controller.text;
      _dirty = false;
    });
    _updateWindowTitle();
  }

  Future<void> _saveAs() async {
    final location = await getSaveLocation(
      acceptedTypeGroups: [_kFileTypes],
      suggestedName: _path == null ? 'Untitled.md' : _docName,
    );
    if (location == null) return;
    _path = location.path;
    await _save();
  }

  // ---- Formatting commands -----------------------------------------------

  /// Wrap the selection in [mark]; with a collapsed selection, wrap the word
  /// under the caret, or insert an empty pair with the caret inside.
  void _wrapSelection(String mark) {
    var sel = _controller.selection;
    if (!sel.isValid) return;
    final text = _controller.text;
    if (sel.isCollapsed) {
      bool isWordChar(String c) => _kWordRe.hasMatch(c);
      var s = sel.start, e = sel.start;
      while (s > 0 && isWordChar(text[s - 1])) {
        s--;
      }
      while (e < text.length && isWordChar(text[e])) {
        e++;
      }
      if (s == e) {
        _controller.value = TextEditingValue(
          text: text.replaceRange(sel.start, sel.start, '$mark$mark'),
          selection: TextSelection.collapsed(offset: sel.start + mark.length),
        );
        _editorFocus.requestFocus();
        return;
      }
      sel = TextSelection(baseOffset: s, extentOffset: e);
    }
    final inner = sel.textInside(text);
    _controller.value = TextEditingValue(
      text: text.replaceRange(sel.start, sel.end, '$mark$inner$mark'),
      selection: TextSelection(
        baseOffset: sel.start + mark.length,
        extentOffset: sel.end + mark.length,
      ),
    );
    _editorFocus.requestFocus();
  }

  (int, int) _currentLineBounds() {
    final sel = _controller.selection;
    final text = _controller.text;
    final anchor = sel.isValid ? sel.start : 0;
    var lineStart = anchor;
    while (lineStart > 0 && text[lineStart - 1] != '\n') {
      lineStart--;
    }
    var lineEnd = anchor;
    while (lineEnd < text.length && text[lineEnd] != '\n') {
      lineEnd++;
    }
    return (lineStart, lineEnd);
  }

  void _replaceCurrentLine(String Function(String line) transform) {
    final sel = _controller.selection;
    if (!sel.isValid) return;
    final text = _controller.text;
    final (lineStart, lineEnd) = _currentLineBounds();
    final line = text.substring(lineStart, lineEnd);
    final newLine = transform(line);
    final delta = newLine.length - line.length;
    _controller.value = TextEditingValue(
      text: text.replaceRange(lineStart, lineEnd, newLine),
      selection: TextSelection.collapsed(
          offset:
              (sel.start + delta).clamp(lineStart, lineStart + newLine.length)),
    );
    _editorFocus.requestFocus();
  }

  void _cycleHeading() {
    _replaceCurrentLine((line) {
      final match = RegExp(r'^(#{1,6})\s').firstMatch(line);
      if (match == null) return '# $line';
      if (match.group(1)!.length >= 6) return line.substring(match.end);
      return '#$line';
    });
  }

  void _toggleList() {
    _replaceCurrentLine((line) {
      final match = RegExp(r'^(\s*)-\s').firstMatch(line);
      if (match != null) return line.substring(match.end);
      return '- $line';
    });
  }

  void _toggleFocusMode() {
    setState(() => _controller.focusMode = !_controller.focusMode);
  }

  void _setViewMode(MarkdownViewMode mode) {
    setState(() => _controller.viewMode = mode);
    widget.settings.setViewMode(mode.name);
  }

  void _cycleViewMode() {
    const modes = MarkdownViewMode.values;
    _setViewMode(
        modes[(modes.indexOf(_controller.viewMode) + 1) % modes.length]);
  }

  void _toggleSidebar() {
    setState(() => _sidebarVisible = !_sidebarVisible);
    if (_sidebarVisible && _sidebarRoot != null) {
      // Trace's sidebar is keyboard-driven: focus it when opened.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _sidebarFocus.requestFocus();
      });
    } else {
      _editorFocus.requestFocus();
    }
  }

  Future<void> _pickSidebarRoot() async {
    final dir = await getDirectoryPath();
    if (dir != null) {
      widget.settings.setSidebarRoot(dir);
      setState(() => _sidebarVisible = true);
    }
  }

  String? get _sidebarRoot =>
      widget.settings.sidebarRoot ?? (_path == null ? null : p.dirname(_path!));

  void _zoom(double delta) {
    widget.settings
        .setEditorFontSize(widget.settings.editorFontSize + delta);
    setState(() {});
  }

  void _zoomReset() {
    widget.settings.setEditorFontSize(15.5);
    setState(() {});
  }

  void _onEscape() {
    if (_findVisible) {
      _closeFind();
    } else if (_controller.focusMode) {
      _toggleFocusMode();
    }
  }

  // ---- Smart editing keys ------------------------------------------------

  static final _taskLineRe = RegExp(r'^(\s*)([-*+])(\s+)\[[ xX]\](\s*)(.*)$');
  static final _bulletLineRe = RegExp(r'^(\s*)([-*+])(\s+)(.*)$');
  static final _orderedLineRe = RegExp(r'^(\s*)(\d{1,9})([.)])(\s+)(.*)$');

  KeyEventResult _onEditorKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final hk = HardwareKeyboard.instance;
    if (hk.isControlPressed || hk.isAltPressed || hk.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (hk.isShiftPressed) return KeyEventResult.ignored;
      return _handleEnter();
    }
    if (key == LogicalKeyboardKey.tab) {
      return _handleTab(outdent: hk.isShiftPressed);
    }
    final ch = event.character;
    if (ch != null && ch.length == 1) return _handleCharacter(ch);
    return KeyEventResult.ignored;
  }

  /// Enter inside a list continues it (checkbox lists get a fresh `[ ]`,
  /// numbered lists increment); Enter on an empty item exits the list.
  KeyEventResult _handleEnter() {
    final sel = _controller.selection;
    if (!sel.isValid || !sel.isCollapsed) return KeyEventResult.ignored;
    final text = _controller.text;
    final (lineStart, lineEnd) = _currentLineBounds();
    final line = text.substring(lineStart, lineEnd);

    final task = _taskLineRe.firstMatch(line);
    final bullet = task == null ? _bulletLineRe.firstMatch(line) : null;
    final ordered =
        task == null && bullet == null ? _orderedLineRe.firstMatch(line) : null;
    if (task == null && bullet == null && ordered == null) {
      return KeyEventResult.ignored;
    }

    final content = task?.group(5) ?? bullet?.group(4) ?? ordered!.group(5)!;
    if (content.trim().isEmpty && sel.start >= lineEnd) {
      // Empty item: exit the list.
      _controller.value = TextEditingValue(
        text: text.replaceRange(lineStart, lineEnd, ''),
        selection: TextSelection.collapsed(offset: lineStart),
      );
      return KeyEventResult.handled;
    }

    final String marker;
    if (task != null) {
      marker = '${task.group(1)}${task.group(2)}${task.group(3)}[ ] ';
    } else if (bullet != null) {
      marker = '${bullet.group(1)}${bullet.group(2)}${bullet.group(3)}';
    } else {
      final n = int.parse(ordered!.group(2)!) + 1;
      marker = '${ordered.group(1)}$n${ordered.group(3)}${ordered.group(4)}';
    }
    _controller.value = TextEditingValue(
      text: text.replaceRange(sel.start, sel.start, '\n$marker'),
      selection:
          TextSelection.collapsed(offset: sel.start + 1 + marker.length),
    );
    return KeyEventResult.handled;
  }

  KeyEventResult _handleTab({required bool outdent}) {
    final sel = _controller.selection;
    if (!sel.isValid) return KeyEventResult.ignored;
    final text = _controller.text;
    final (lineStart, _) = _currentLineBounds();
    final line = text.substring(lineStart, text.indexOf('\n', lineStart) == -1
        ? text.length
        : text.indexOf('\n', lineStart));
    final isList = _taskLineRe.hasMatch(line) ||
        _bulletLineRe.hasMatch(line) ||
        _orderedLineRe.hasMatch(line);

    if (outdent) {
      var remove = 0;
      if (line.startsWith('  ')) {
        remove = 2;
      } else if (line.startsWith(' ') || line.startsWith('\t')) {
        remove = 1;
      }
      if (remove > 0) {
        _controller.value = TextEditingValue(
          text: text.replaceRange(lineStart, lineStart + remove, ''),
          selection: TextSelection.collapsed(
              offset: math.max(lineStart, sel.start - remove)),
        );
      }
      return KeyEventResult.handled;
    }
    if (isList) {
      _controller.value = TextEditingValue(
        text: text.replaceRange(lineStart, lineStart, '  '),
        selection: TextSelection.collapsed(offset: sel.start + 2),
      );
      return KeyEventResult.handled;
    }
    // Plain Tab types two spaces instead of moving focus.
    _controller.value = TextEditingValue(
      text: text.replaceRange(sel.start, sel.end, '  '),
      selection: TextSelection.collapsed(offset: sel.start + 2),
    );
    return KeyEventResult.handled;
  }

  static const _wrapPairs = {
    '*': '*',
    '_': '_',
    '~': '~',
    '`': '`',
    '"': '"',
    '(': ')',
    '[': ']',
  };

  /// Typing a pair character with text selected wraps it; `(`/`[`/`` ` ``
  /// auto-close on an empty selection, and typing the closing half skips
  /// over one that is already there.
  KeyEventResult _handleCharacter(String ch) {
    final sel = _controller.selection;
    if (!sel.isValid) return KeyEventResult.ignored;
    final text = _controller.text;

    if (!sel.isCollapsed) {
      final close = _wrapPairs[ch];
      if (close == null) return KeyEventResult.ignored;
      final inner = sel.textInside(text);
      _controller.value = TextEditingValue(
        text: text.replaceRange(sel.start, sel.end, '$ch$inner$close'),
        selection: TextSelection(
            baseOffset: sel.start + 1, extentOffset: sel.end + 1),
      );
      return KeyEventResult.handled;
    }

    final next = sel.start < text.length ? text[sel.start] : '';
    if ((ch == ')' || ch == ']' || ch == '`') && next == ch) {
      _controller.selection = TextSelection.collapsed(offset: sel.start + 1);
      return KeyEventResult.handled;
    }
    if (ch == '(' || ch == '[' || ch == '`') {
      final close = _wrapPairs[ch]!;
      _controller.value = TextEditingValue(
        text: text.replaceRange(sel.start, sel.start, '$ch$close'),
        selection: TextSelection.collapsed(offset: sel.start + 1),
      );
      return KeyEventResult.handled;
    }

    // Smart typography (optional): curly quotes and -- → em dash.
    if (widget.settings.smartTypography) {
      final prev = sel.start > 0 ? text[sel.start - 1] : '';
      if (ch == '-' && prev == '-') {
        _controller.value = TextEditingValue(
          text: text.replaceRange(sel.start - 1, sel.start, '—'),
          selection: TextSelection.collapsed(offset: sel.start),
        );
        return KeyEventResult.handled;
      }
      if (ch == '"' || ch == "'") {
        final opens =
            prev.isEmpty || RegExp(r'[\s(\[{—–\-]').hasMatch(prev);
        final curly = ch == '"'
            ? (opens ? '“' : '”')
            : (opens ? '‘' : '’');
        _controller.value = TextEditingValue(
          text: text.replaceRange(sel.start, sel.start, curly),
          selection: TextSelection.collapsed(offset: sel.start + 1),
        );
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  // ---- Document switching, quick open, export ----------------------------

  /// Ctrl+Tab: jump back to the previously open document (MRU toggle).
  void _switchToPrevious() {
    for (final recent in widget.settings.recentFiles) {
      if (recent != _path && File(recent).existsSync()) {
        _openPath(recent);
        return;
      }
    }
  }

  void _showQuickOpen() {
    final root = _sidebarRoot;
    if (root == null && widget.settings.recentFiles.isEmpty) {
      _openDialog();
      return;
    }
    showQuickOpen(
      context,
      _palette,
      root ?? p.dirname(widget.settings.recentFiles.first),
      widget.settings.recentFiles,
      (path, offset) async {
        await _openPath(path);
        if (offset != null && _path == path) {
          final caret = offset.clamp(0, _controller.text.length);
          _controller.selection = TextSelection.collapsed(offset: caret);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToOffset(caret);
          });
        }
      },
    );
  }

  Future<void> _exportHtml() async {
    final location = await getSaveLocation(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'HTML', extensions: ['html'])
      ],
      suggestedName:
          '${_path == null ? 'Untitled' : p.basenameWithoutExtension(_path!)}.html',
    );
    if (location == null) return;
    final body = md.markdownToHtml(_controller.text,
        extensionSet: md.ExtensionSet.gitHubFlavored);
    final title = const HtmlEscape().convert(_docName);
    final html = '<!doctype html><html><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        '<title>$title</title><style>'
        'body{max-width:720px;margin:3rem auto;padding:0 1.5rem;'
        'font:16px/1.7 -apple-system,"Segoe UI",Roboto,sans-serif;'
        'color:#2c2c2b;background:#fdfdfc}'
        'h1,h2,h3{line-height:1.3}a{color:#0969da}'
        'code{background:#f0efec;padding:.15em .35em;border-radius:4px;'
        'font-size:.9em}pre{background:#f0efec;padding:1em;border-radius:8px;'
        'overflow-x:auto}pre code{background:none;padding:0}'
        'blockquote{border-left:3px solid #d0cfcb;margin-left:0;'
        'padding-left:1em;color:#6b6a66}'
        'table{border-collapse:collapse}td,th{border:1px solid #d0cfcb;'
        'padding:.35em .7em}img{max-width:100%}'
        '</style></head><body>$body</body></html>';
    await File(location.path).writeAsString(html);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 2),
          content: Text('Exported to ${p.basename(location.path)}')));
    }
  }

  Future<void> _exportPrintPdf() async {
    final location = await getSaveLocation(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'HTML / Printable Document', extensions: ['html'])
      ],
      suggestedName:
          '${_path == null ? 'Untitled' : p.basenameWithoutExtension(_path!)}-print.html',
    );
    if (location == null) return;
    final body = md.markdownToHtml(_controller.text,
        extensionSet: md.ExtensionSet.gitHubFlavored);
    final title = const HtmlEscape().convert(_docName);
    final html = '<!doctype html><html><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        '<title>$title</title><style>'
        '@page { size: A4; margin: 25mm 20mm; }'
        'body{max-width:720px;margin:2.5rem auto;padding:0 1.5rem;'
        'font:11pt/1.7 Charter,"Iowan Old Style","Georgia",Cambria,serif;color:#111;background:#fff}'
        'h1,h2,h3,h4{font-family:-apple-system,"Segoe UI",Helvetica,Arial,sans-serif;font-weight:600;color:#000;line-height:1.25;margin-top:1.8em;margin-bottom:0.6em}'
        'h1{font-size:24pt;border-bottom:1px solid #e5e5e5;padding-bottom:0.3em;margin-top:0}'
        'h2{font-size:18pt;border-bottom:1px solid #f0f0f0;padding-bottom:0.2em}'
        'h3{font-size:14pt}'
        'p{margin:1em 0}'
        'a{color:#0969da;text-decoration:none}'
        'code{font-family:Consolas,Menlo,"DejaVu Sans Mono",monospace;font-size:9.5pt;background:#f5f5f4;padding:0.15em 0.3em;border-radius:3px}'
        'pre{background:#f8f8f7;border:1px solid #e8e8e6;border-radius:6px;padding:1em;overflow-x:auto;font-family:Consolas,Menlo,monospace;font-size:9pt;line-height:1.5;page-break-inside:avoid}'
        'pre code{background:none;padding:0}'
        'blockquote{border-left:3px solid #ccc;margin:1.2em 0;padding-left:1em;color:#555;font-style:italic}'
        'table{border-collapse:collapse;width:100%;margin:1.2em 0;page-break-inside:avoid}'
        'th,td{border:1px solid #ddd;padding:0.4em 0.8em;text-align:left;font-size:10pt}'
        'th{background:#f9f9f9;font-weight:600}'
        'hr{border:none;border-top:1px solid #e0e0e0;margin:2em 0}'
        'img{max-width:100%;height:auto;display:block;margin:1.5em auto}'
        '@media print {'
        '  body{max-width:100%;margin:0;padding:0}'
        '  h1,h2,h3{page-break-after:avoid}'
        '  pre,blockquote,table,img{page-break-inside:avoid}'
        '}'
        '</style></head><body>'
        '$body'
        '<script>window.addEventListener("DOMContentLoaded", function() { setTimeout(function() { window.print(); }, 400); });</script>'
        '</body></html>';
    await File(location.path).writeAsString(html);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () => launchUrl(Uri.file(location.path)),
          ),
          content: Text('Saved printable document to ${p.basename(location.path)}')));
    }
    try {
      await launchUrl(Uri.file(location.path));
    } catch (_) {}
  }

  Future<void> _promptDailyWordGoal() async {
    final controller = TextEditingController(
        text: widget.settings.dailyWordGoal > 0
            ? widget.settings.dailyWordGoal.toString()
            : '750');
    final goal = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Daily Writing Goal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Set a target word count for your drafting sessions. An ambient progress ring will reflect your completion in the statistics popover.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Word Goal (0 to disable)',
                hintText: 'e.g. 500, 750, 1000',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final val = int.tryParse(controller.text.trim()) ?? 0;
              Navigator.of(context).pop(val);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (goal != null) {
      widget.settings.setDailyWordGoal(goal);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(goal > 0
              ? 'Daily word goal set to $goal words.'
              : 'Daily word goal disabled.'),
        ));
      }
    }
  }

  void _toggleEInkMode() {
    widget.settings.setEInkMode(!widget.settings.eInkMode);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(widget.settings.eInkMode
            ? 'E-Ink high-contrast mode enabled.'
            : 'E-Ink high-contrast mode disabled.'),
      ));
    }
  }

  // ---- Click interactions ------------------------------------------------

  void _handleEditorTap() {
    final sel = _controller.selection;
    if (!sel.isValid || !sel.isCollapsed) return;
    final text = _controller.text;
    final (lineStart, lineEnd) = _currentLineBounds();
    final line = text.substring(lineStart, lineEnd);
    final rel = sel.start - lineStart;

    if (HardwareKeyboard.instance.isControlPressed) {
      for (final m in RegExp(r'\[[^\]\n]*\]\(([^)\n]+)\)').allMatches(line)) {
        if (rel >= m.start && rel <= m.end) {
          _openLink(m.group(1)!);
          return;
        }
      }
      for (final m in RegExp(r'https?://[^\s)\]]+').allMatches(line)) {
        if (rel >= m.start && rel <= m.end) {
          _openLink(m.group(0)!);
          return;
        }
      }
      return;
    }

    // Clicking a checkbox toggles it.
    final task = RegExp(r'^(\s*[-*+]\s+)\[([ xX])\]').firstMatch(line);
    if (task != null) {
      final boxStart = task.group(1)!.length;
      if (rel >= boxStart && rel <= boxStart + 3) {
        final abs = lineStart + boxStart + 1;
        final replacement = task.group(2)!.trim().isEmpty ? 'x' : ' ';
        _controller.value = TextEditingValue(
          text: text.replaceRange(abs, abs + 1, replacement),
          selection: sel,
        );
      }
    }
  }

  Future<void> _openLink(String url) async {
    var u = url.trim();
    if (!u.contains('://')) {
      if (!u.contains('.') || u.contains(' ')) return; // relative path
      u = 'https://$u';
    }
    try {
      await launchUrl(Uri.parse(u));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not open $u')));
      }
    }
  }

  // ---- Find & replace ----------------------------------------------------

  void _openFind({required bool replace}) {
    final sel = _controller.selection;
    if (sel.isValid && !sel.isCollapsed) {
      final selected = sel.textInside(_controller.text);
      if (!selected.contains('\n') && selected.length < 100) {
        _findController.text = selected;
      }
    }
    setState(() {
      _findVisible = true;
      _replaceVisible = replace;
      _matchIndex = 0;
    });
    _updateMatches();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _findFocus.requestFocus();
      _findController.selection = TextSelection(
          baseOffset: 0, extentOffset: _findController.text.length);
    });
  }

  void _closeFind() {
    setState(() {
      _findVisible = false;
      _replaceVisible = false;
    });
    _controller.setSearch('');
    _editorFocus.requestFocus();
  }

  void _updateMatches() {
    final q = _findController.text;
    _controller.setSearch(q, current: -1);
    final matches = _controller.searchMatches;
    if (matches.isEmpty) {
      _matchIndex = -1;
    } else {
      _matchIndex = _matchIndex.clamp(0, matches.length - 1);
      _controller.setSearch(q, current: matches[_matchIndex]);
    }
    if (mounted) setState(() {});
  }

  void _findStep(int delta) {
    final matches = _controller.searchMatches;
    if (matches.isEmpty) return;
    _matchIndex =
        ((_matchIndex + delta) % matches.length + matches.length) %
            matches.length;
    final offset = matches[_matchIndex];
    final q = _findController.text;
    _controller.setSearch(q, current: offset);
    _controller.selection =
        TextSelection(baseOffset: offset, extentOffset: offset + q.length);
    _scrollToOffset(offset);
    setState(() {});
  }

  void _replaceCurrent() {
    final matches = _controller.searchMatches;
    if (_matchIndex < 0 || _matchIndex >= matches.length) return;
    final offset = matches[_matchIndex];
    final len = _findController.text.length;
    final replacement = _replaceController.text;
    final text = _controller.text;
    _controller.value = TextEditingValue(
      text: text.replaceRange(offset, offset + len, replacement),
      selection:
          TextSelection.collapsed(offset: offset + replacement.length),
    );
    _updateMatches();
    _findStep(0);
  }

  void _replaceAll() {
    final matches = List<int>.from(_controller.searchMatches);
    if (matches.isEmpty) return;
    final len = _findController.text.length;
    final replacement = _replaceController.text;
    var text = _controller.text;
    for (final offset in matches.reversed) {
      text = text.replaceRange(offset, offset + len, replacement);
    }
    _controller.value = TextEditingValue(
      text: text,
      selection: const TextSelection.collapsed(offset: 0),
    );
    _matchIndex = 0;
    _updateMatches();
  }

  KeyEventResult _onFindKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        _findStep(HardwareKeyboard.instance.isShiftPressed ? -1 : 1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        _closeFind();
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  TextStyle get _editorTextStyle => TextStyle(
        fontSize: widget.settings.editorFontSize,
        height: widget.settings.lineHeight,
        letterSpacing: 0.1,
      );

  /// Exact vertical position of [offset], measured by laying the text out at
  /// the editor's real width. Falls back to null for very large documents.
  double? _caretYFor(int offset) {
    final text = _controller.text;
    if (text.length > 200000) return null;
    try {
      final painter = TextPainter(
        text: TextSpan(text: text, style: _editorTextStyle),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: _editorWidth);
      final y = painter
          .getOffsetForCaret(TextPosition(offset: offset), Rect.zero)
          .dy;
      painter.dispose();
      return y;
    } catch (_) {
      return null;
    }
  }

  void _scrollToOffset(int offset, {bool animate = true, double align = 0.35}) {
    if (!_scroll.hasClients || _controller.text.isEmpty) return;
    final max = _scroll.position.maxScrollExtent;
    final viewport = _scroll.position.viewportDimension;
    final y = _caretYFor(offset);
    final double target;
    if (y != null) {
      target = (y + _kTitleBarHeight + 14 - viewport * align).clamp(0.0, max);
    } else {
      target = (max * (offset / _controller.text.length)).clamp(0.0, max);
    }
    if (animate) {
      _scroll.animateTo(target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic);
    } else {
      _scroll.jumpTo(target);
    }
  }

  /// Typewriter scrolling: in focus mode the caret line stays vertically
  /// centered — the text moves, you don't.
  void _typewriterScroll() {
    if (!_controller.focusMode || !_controller.selection.isValid) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scrollToOffset(_controller.selection.start,
          animate: false, align: 0.5);
    });
  }

  // ---- Copy as Rich Text -------------------------------------------------

  Future<void> _copyRichText() async {
    final sel = _controller.selection;
    final source = (sel.isValid && !sel.isCollapsed)
        ? sel.textInside(_controller.text)
        : _controller.text;
    if (source.trim().isEmpty) return;
    final html =
        md.markdownToHtml(source, extensionSet: md.ExtensionSet.gitHubFlavored);
    var rich = false;
    if (Platform.isWindows) {
      try {
        final f = File(p.join(Directory.systemTemp.path, 'notbad_rich.html'));
        await f.writeAsString(html);
        final r = await Process.run('powershell', [
          '-NoProfile',
          '-Command',
          "Set-Clipboard -AsHtml (Get-Content -Raw '${f.path}')",
        ]);
        rich = r.exitCode == 0;
      } catch (_) {}
    }
    if (!rich) {
      await Clipboard.setData(ClipboardData(text: source));
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(rich ? 'Copied as rich text' : 'Copied as Markdown')));
    }
  }

  // ---- Table of contents -------------------------------------------------

  List<(int level, String text, int offset)> _headings() {
    final result = <(int, String, int)>[];
    var offset = 0;
    var inFence = false;
    for (final line in _controller.text.split('\n')) {
      if (RegExp(r'^\s*(```|~~~)').hasMatch(line)) inFence = !inFence;
      if (!inFence) {
        final m = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line);
        if (m != null) {
          result.add((m.group(1)!.length, m.group(2)!.trim(), offset));
        }
      }
      offset += line.length + 1;
    }
    return result;
  }

  void _jumpTo(int offset) {
    _controller.selection = TextSelection.collapsed(offset: offset);
    _editorFocus.requestFocus();
    _scrollToOffset(offset);
  }

  // ---- Command palette ---------------------------------------------------

  void _showPalette() =>
      showCommandPalette(context, _palette, _rootActions());

  void _openSub(List<PaletteAction> Function() actions) {
    // Reopen the palette one level deeper on the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showCommandPalette(context, _palette, actions());
    });
  }

  String _cap(String s) => '${s[0].toUpperCase()}${s.substring(1)}';

  List<PaletteAction> _viewModeActions({bool searchOnly = false}) => [
        for (final mode in MarkdownViewMode.values)
          PaletteAction(
              title: 'View: ${mode.label}',
              category: 'View',
              searchOnly: searchOnly,
              checked: _controller.viewMode == mode,
              run: () => _setViewMode(mode)),
      ];

  List<PaletteAction> _appearanceActions({bool searchOnly = false}) => [
        for (final mode in ThemeMode.values)
          PaletteAction(
              title: 'Appearance: ${_cap(mode.name)}',
              category: 'Settings',
              searchOnly: searchOnly,
              checked: widget.settings.themeMode == mode,
              run: () => widget.settings.setThemeMode(mode)),
      ];

  List<PaletteAction> _accentActions({bool searchOnly = false}) => [
        for (final entry in kAccents.entries)
          PaletteAction(
              title: 'Accent: ${entry.value.name}',
              category: 'Settings',
              searchOnly: searchOnly,
              checked: widget.settings.accent == entry.key,
              swatch: entry.value
                  .forBrightness(Theme.of(context).brightness),
              run: () => widget.settings.setAccent(entry.key)),
      ];

  List<PaletteAction> _lineHeightActions({bool searchOnly = false}) => [
        for (final (label, value) in [
          ('Tight', 1.6),
          ('Normal', 1.85),
          ('Relaxed', 2.1)
        ])
          PaletteAction(
              title: 'Line Height: $label',
              category: 'Settings',
              searchOnly: searchOnly,
              checked: widget.settings.lineHeight == value,
              run: () => widget.settings.setLineHeight(value)),
      ];

  List<PaletteAction> _settingsActions({bool searchOnly = false}) {
    final settings = widget.settings;
    return [
      PaletteAction(
          title: 'Appearance…',
          category: 'Settings',
          subtitle: _cap(settings.themeMode.name),
          searchOnly: searchOnly,
          run: () => _openSub(_appearanceActions)),
      PaletteAction(
          title: 'Accent Color…',
          category: 'Settings',
          subtitle: kAccents[settings.accent]?.name,
          searchOnly: searchOnly,
          run: () => _openSub(_accentActions)),
      PaletteAction(
          title: 'Line Height…',
          category: 'Settings',
          searchOnly: searchOnly,
          run: () => _openSub(_lineHeightActions)),
      PaletteAction(
          title: 'Toggle Autosave',
          category: 'Settings',
          checked: settings.autosave,
          searchOnly: searchOnly,
          run: () => settings.setAutosave(!settings.autosave)),
      PaletteAction(
          title: 'Toggle Smart Typography',
          category: 'Settings',
          subtitle: 'Curly quotes and — from --',
          checked: settings.smartTypography,
          searchOnly: searchOnly,
          run: () => settings.setSmartTypography(!settings.smartTypography)),
      PaletteAction(
          title: 'Zoom In',
          category: 'Settings',
          shortcut: 'Ctrl+=',
          searchOnly: searchOnly,
          run: () => _zoom(1)),
      PaletteAction(
          title: 'Zoom Out',
          category: 'Settings',
          shortcut: 'Ctrl+-',
          searchOnly: searchOnly,
          run: () => _zoom(-1)),
      PaletteAction(
          title: 'Reset Zoom',
          category: 'Settings',
          shortcut: 'Ctrl+0',
          searchOnly: searchOnly,
          run: _zoomReset),
      PaletteAction(
          title: 'Choose Sidebar Folder…',
          category: 'Settings',
          searchOnly: searchOnly,
          run: _pickSidebarRoot),
    ];
  }

  /// The root palette: a short, browsable list. Everything nested stays
  /// reachable by typing — search matches the hidden leaf actions too.
  List<PaletteAction> _rootActions() {
    final settings = widget.settings;
    return [
      PaletteAction(
          title: 'New', category: 'File', shortcut: 'Ctrl+N', run: _newDocument),
      PaletteAction(
          title: 'Open…',
          category: 'File',
          shortcut: 'Ctrl+O',
          run: _openDialog),
      PaletteAction(
          title: 'Open Document…',
          category: 'File',
          subtitle: 'Search files and their contents',
          shortcut: 'Ctrl+Shift+O',
          run: _showQuickOpen),
      PaletteAction(
          title: 'Save', category: 'File', shortcut: 'Ctrl+S', run: _save),
      PaletteAction(
          title: 'Save As…',
          category: 'File',
          shortcut: 'Ctrl+Shift+S',
          searchOnly: true,
          run: _saveAs),
      PaletteAction(
          title: 'Switch to Previous Document',
          category: 'File',
          shortcut: 'Ctrl+Tab',
          searchOnly: true,
          run: _switchToPrevious),
      PaletteAction(
          title: 'Export as HTML…',
          category: 'File',
          searchOnly: true,
          run: _exportHtml),
      PaletteAction(
          title: 'Export as Printable PDF / Document…',
          category: 'File',
          searchOnly: true,
          run: _exportPrintPdf),
      PaletteAction(
          title: 'Set Daily Writing Goal…',
          category: 'Writing',
          subtitle: settings.dailyWordGoal > 0
              ? '${settings.dailyWordGoal} words'
              : 'Disabled',
          searchOnly: true,
          run: _promptDailyWordGoal),
      PaletteAction(
          title: 'Toggle E-Ink / High-Contrast Mode',
          category: 'View',
          checked: settings.eInkMode,
          searchOnly: true,
          run: _toggleEInkMode),
      PaletteAction(
          title: 'Find…',
          category: 'Edit',
          shortcut: 'Ctrl+F',
          run: () => _openFind(replace: false)),
      PaletteAction(
          title: 'Find and Replace…',
          category: 'Edit',
          shortcut: 'Ctrl+H',
          searchOnly: true,
          run: () => _openFind(replace: true)),
      PaletteAction(
          title: 'Copy as Rich Text',
          category: 'Edit',
          shortcut: 'Ctrl+Alt+C',
          run: _copyRichText),
      PaletteAction(
          title: 'Toggle Sidebar',
          category: 'View',
          shortcut: 'Ctrl+\\',
          run: _toggleSidebar),
      PaletteAction(
          title: 'Toggle Focus Mode',
          category: 'View',
          shortcut: 'Ctrl+Shift+F',
          checked: _controller.focusMode,
          run: _toggleFocusMode),
      PaletteAction(
          title: 'View Mode…',
          category: 'View',
          subtitle: _controller.viewMode.label,
          shortcut: 'Ctrl+Shift+H',
          run: () => _openSub(_viewModeActions)),
      PaletteAction(
          title: 'Settings…',
          category: 'App',
          subtitle:
              '${kAccents[settings.accent]?.name} · ${_cap(settings.themeMode.name)}'
              '${settings.autosave ? ' · Autosave' : ''}',
          run: () => _openSub(_settingsActions)),
      // Hidden leaves: found by search, not shown while browsing.
      ..._viewModeActions(searchOnly: true),
      ..._settingsActions(searchOnly: true),
      ..._appearanceActions(searchOnly: true),
      ..._accentActions(searchOnly: true),
      ..._lineHeightActions(searchOnly: true),
      for (final recent in settings.recentFiles.take(5))
        PaletteAction(
          title: p.basenameWithoutExtension(recent),
          subtitle: recent,
          category: 'Recent',
          run: () => _openPath(recent),
        ),
    ];
  }

  // ---- UI ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = _palette;
    _controller.palette = palette;

    final shortcuts = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.escape): _onEscape,
      const SingleActivator(LogicalKeyboardKey.f3): () => _findStep(1),
      const SingleActivator(LogicalKeyboardKey.f3, shift: true): () =>
          _findStep(-1),
      for (final meta in [false, true]) ...{
        SingleActivator(LogicalKeyboardKey.keyK, control: !meta, meta: meta):
            _showPalette,
        SingleActivator(LogicalKeyboardKey.keyS, control: !meta, meta: meta):
            _save,
        SingleActivator(LogicalKeyboardKey.keyS,
            control: !meta, meta: meta, shift: true): _saveAs,
        SingleActivator(LogicalKeyboardKey.keyO, control: !meta, meta: meta):
            _openDialog,
        SingleActivator(LogicalKeyboardKey.keyO,
            control: !meta, meta: meta, shift: true): _showQuickOpen,
        SingleActivator(LogicalKeyboardKey.tab, control: !meta, meta: meta):
            _switchToPrevious,
        SingleActivator(LogicalKeyboardKey.keyN, control: !meta, meta: meta):
            _newDocument,
        SingleActivator(LogicalKeyboardKey.keyF, control: !meta, meta: meta):
            () => _openFind(replace: false),
        SingleActivator(LogicalKeyboardKey.keyH, control: !meta, meta: meta):
            () => _openFind(replace: true),
        SingleActivator(LogicalKeyboardKey.keyB, control: !meta, meta: meta):
            () => _wrapSelection('**'),
        SingleActivator(LogicalKeyboardKey.keyI, control: !meta, meta: meta):
            () => _wrapSelection('*'),
        SingleActivator(LogicalKeyboardKey.keyC,
            control: !meta, meta: meta, alt: true): _copyRichText,
        SingleActivator(LogicalKeyboardKey.backslash,
            control: !meta, meta: meta): _toggleSidebar,
        SingleActivator(LogicalKeyboardKey.keyF,
            control: !meta, meta: meta, shift: true): _toggleFocusMode,
        SingleActivator(LogicalKeyboardKey.keyH,
            control: !meta, meta: meta, shift: true): _cycleViewMode,
        SingleActivator(LogicalKeyboardKey.equal, control: !meta, meta: meta):
            () => _zoom(1),
        SingleActivator(LogicalKeyboardKey.minus, control: !meta, meta: meta):
            () => _zoom(-1),
        SingleActivator(LogicalKeyboardKey.numpadAdd,
            control: !meta, meta: meta): () => _zoom(1),
        SingleActivator(LogicalKeyboardKey.numpadSubtract,
            control: !meta, meta: meta): () => _zoom(-1),
        SingleActivator(LogicalKeyboardKey.digit0, control: !meta, meta: meta):
            _zoomReset,
      },
    };

    final showSidebar = _sidebarVisible && _sidebarRoot != null;

    return CallbackShortcuts(
      bindings: shortcuts,
      child: Scaffold(
        backgroundColor: palette.bg,
        body: DropTarget(
          onDragDone: (detail) {
            for (final f in detail.files) {
              if (_kWritingExtensions
                  .contains(p.extension(f.path).toLowerCase())) {
                _openPath(f.path);
                break;
              }
            }
          },
          child: Stack(
            children: [
              Row(
                children: [
                  ClipRect(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      width: showSidebar ? 230 : 0,
                      child: _sidebarRoot == null
                          ? null
                          : OverflowBox(
                              minWidth: 230,
                              maxWidth: 230,
                              alignment: Alignment.centerRight,
                              child: FileSidebar(
                                palette: palette,
                                rootPath: _sidebarRoot!,
                                currentFile: _path,
                                onOpenFile: _openPath,
                                onPickRoot: _pickSidebarRoot,
                                focusNode: _sidebarFocus,
                                onExit: () => _editorFocus.requestFocus(),
                              ),
                            ),
                    ),
                  ),
                  Expanded(
                    child: MouseRegion(
                      opaque: false,
                      onHover: (_) {
                        if (!_toolbarVisible) {
                          setState(() => _toolbarVisible = true);
                        }
                      },
                      child: Stack(
                        children: [
                          _buildEditor(palette),
                          if (_showWelcome) _buildWelcome(palette),
                          Positioned(
                            top: _kTitleBarHeight + 10,
                            left: 20,
                            child: HoverToc(
                              palette: palette,
                              headings: _headings(),
                              onJump: _jumpTo,
                            ),
                          ),
                          if (_findVisible)
                            Positioned(
                              top: _kTitleBarHeight + 6,
                              right: 16,
                              child: _buildFindBar(palette),
                            ),
                          Positioned(
                            bottom: 16,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOut,
                                opacity: _toolbarVisible ? 1 : 0,
                                child: IgnorePointer(
                                  ignoring: !_toolbarVisible,
                                  child: _buildToolbar(palette),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _buildTitleBar(palette),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFindBar(TracePalette palette) {
    return FindReplaceBar(
      palette: palette,
      findController: _findController,
      replaceController: _replaceController,
      findFocus: _findFocus,
      replaceVisible: _replaceVisible,
      matchIndex: _matchIndex,
      matchCount: _controller.searchMatches.length,
      onFindChanged: (_) {
        _matchIndex = 0;
        _updateMatches();
      },
      onFindStep: _findStep,
      onToggleReplace: () => setState(() => _replaceVisible = !_replaceVisible),
      onClose: _closeFind,
      onReplaceCurrent: _replaceCurrent,
      onReplaceAll: _replaceAll,
      onFindKey: _onFindKey,
    );
  }

  Widget _buildTitleBar(TracePalette palette) {
    return WindowTitleBar(
      palette: palette,
      docName: _docName,
      isDirty: _dirty,
      isMaximized: _isMaximized,
      onToggleSidebar:
          _sidebarRoot == null ? _pickSidebarRoot : _toggleSidebar,
      onShowPalette: _showPalette,
      onToggleMaximize: _toggleMaximize,
    );
  }

  Widget _buildEditor(TracePalette palette) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 56),
          child: LayoutBuilder(
            builder: (context, constraints) {
              _editorWidth = constraints.maxWidth;
              return Focus(
                onKeyEvent: _onEditorKey,
                child: TextField(
                  controller: _controller,
                  focusNode: _editorFocus,
                  scrollController: _scroll,
                  maxLines: null,
                  expands: true,
                  autofocus: true,
                  textAlignVertical: TextAlignVertical.top,
                  onTap: _handleEditorTap,
                  cursorColor: palette.accent,
                  cursorWidth: 2,
                  cursorRadius: const Radius.circular(1),
                  style: _editorTextStyle.copyWith(color: palette.fg),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: _showWelcome
                        ? null
                        : 'A quiet place to write.   ·   Ctrl+K for commands',
                    hintStyle: TextStyle(color: palette.muted),
                    contentPadding: const EdgeInsets.only(
                        top: _kTitleBarHeight + 14, bottom: 90),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  bool get _showWelcome =>
      _path == null && _controller.text.isEmpty && !_welcomeDismissed;

  /// A welcome, not a blank stare: recent files and New/Open on a fresh
  /// launch, gone the moment you type.
  Widget _buildWelcome(TracePalette palette) {
    final recents = [
      for (final r in widget.settings.recentFiles.take(5))
        if (File(r).existsSync()) r,
    ];
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('NotBad',
              style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: palette.fg.withValues(alpha: 0.85))),
          const SizedBox(height: 4),
          Text('A quiet place to write.',
              style: TextStyle(fontSize: 14, color: palette.muted)),
          const SizedBox(height: 22),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.tonal(
                onPressed: () {
                  setState(() => _welcomeDismissed = true);
                  _editorFocus.requestFocus();
                },
                child: const Text('New Document'),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: _openDialog,
                child: const Text('Open…'),
              ),
            ],
          ),
          if (recents.isNotEmpty) ...[
            const SizedBox(height: 26),
            Text('RECENT',
                style: TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                    color: palette.muted)),
            const SizedBox(height: 6),
            for (final r in recents)
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => _openPath(r),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  child: Text(
                    p.basenameWithoutExtension(r),
                    style: TextStyle(fontSize: 13.5, color: palette.accent),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 18),
          Text('Ctrl+K for everything else',
              style: TextStyle(
                  fontSize: 11.5,
                  color: palette.muted.withValues(alpha: 0.8))),
        ],
      ),
    );
  }

  Widget _buildToolbar(TracePalette palette) {
    return FloatingToolbar(
      palette: palette,
      controller: _controller,
      wordCount: _wordCount,
      selWordCount: _selWordCount,
      dailyWordGoal: widget.settings.dailyWordGoal,
      onCycleHeading: _cycleHeading,
      onWrapSelection: _wrapSelection,
      onToggleList: _toggleList,
      onOpenFind: () => _openFind(replace: false),
      onCycleViewMode: _cycleViewMode,
      onToggleFocusMode: _toggleFocusMode,
    );
  }
}
