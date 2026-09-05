import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';

import 'command_palette.dart';
import 'markdown_controller.dart';
import 'settings.dart';
import 'sidebar.dart';
import 'theme.dart';

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
    _autosaveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (widget.settings.autosave && _dirty && _path != null) _save();
    });
    if (widget.initialFile != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _restoreSession());
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
      });
      widget.settings.addRecent(path);
      widget.settings.setSession(path, 0);
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
    return KeyEventResult.ignored;
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

  void _scrollToOffset(int offset) {
    if (_scroll.hasClients && _controller.text.isNotEmpty) {
      final fraction = offset / _controller.text.length;
      _scroll.animateTo(
        (_scroll.position.maxScrollExtent * fraction)
            .clamp(0, _scroll.position.maxScrollExtent),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
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

  void _showPalette() {
    final settings = widget.settings;
    final actions = <PaletteAction>[
      PaletteAction(
          title: 'New', category: 'File', shortcut: 'Ctrl+N', run: _newDocument),
      PaletteAction(
          title: 'Open…',
          category: 'File',
          shortcut: 'Ctrl+O',
          run: _openDialog),
      PaletteAction(
          title: 'Save', category: 'File', shortcut: 'Ctrl+S', run: _save),
      PaletteAction(
          title: 'Save As…',
          category: 'File',
          shortcut: 'Ctrl+Shift+S',
          run: _saveAs),
      PaletteAction(
          title: 'Find…',
          category: 'Edit',
          shortcut: 'Ctrl+F',
          run: () => _openFind(replace: false)),
      PaletteAction(
          title: 'Find and Replace…',
          category: 'Edit',
          shortcut: 'Ctrl+H',
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
      for (final mode in MarkdownViewMode.values)
        PaletteAction(
            title: 'View: ${mode.label}',
            category: 'View',
            shortcut: 'Ctrl+Shift+H',
            checked: _controller.viewMode == mode,
            run: () => _setViewMode(mode)),
      PaletteAction(
          title: 'Zoom In',
          category: 'View',
          shortcut: 'Ctrl+=',
          run: () => _zoom(1)),
      PaletteAction(
          title: 'Zoom Out',
          category: 'View',
          shortcut: 'Ctrl+-',
          run: () => _zoom(-1)),
      PaletteAction(
          title: 'Reset Zoom',
          category: 'View',
          shortcut: 'Ctrl+0',
          run: _zoomReset),
      PaletteAction(
          title: 'Toggle Autosave',
          category: 'File',
          checked: settings.autosave,
          run: () => settings.setAutosave(!settings.autosave)),
      PaletteAction(
          title: 'Choose Sidebar Folder…',
          category: 'File',
          run: _pickSidebarRoot),
      for (final mode in ThemeMode.values)
        PaletteAction(
          title:
              'Appearance: ${mode.name[0].toUpperCase()}${mode.name.substring(1)}',
          category: 'View',
          checked: settings.themeMode == mode,
          run: () => settings.setThemeMode(mode),
        ),
      for (final entry in kAccents.entries)
        PaletteAction(
          title: 'Accent: ${entry.value.name}',
          category: 'View',
          checked: settings.accent == entry.key,
          run: () => settings.setAccent(entry.key),
        ),
      for (final recent in settings.recentFiles)
        PaletteAction(
          title: p.basenameWithoutExtension(recent),
          subtitle: recent,
          category: 'Recent',
          run: () => _openPath(recent),
        ),
    ];
    showCommandPalette(context, _palette, actions);
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
    final matches = _controller.searchMatches;
    final countLabel = matches.isEmpty
        ? (_findController.text.isEmpty ? '' : '0/0')
        : '${_matchIndex + 1}/${matches.length}';

    Widget field(TextEditingController controller, String hint,
        {FocusNode? focus, void Function(String)? onChanged}) {
      return SizedBox(
        width: 190,
        height: 28,
        child: TextField(
          controller: controller,
          focusNode: focus,
          onChanged: onChanged,
          style: TextStyle(color: palette.fg, fontSize: 13),
          cursorColor: palette.accent,
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: TextStyle(color: palette.muted, fontSize: 13),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            filled: true,
            fillColor: palette.bg.withValues(alpha: 0.6),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: palette.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: palette.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: palette.accent),
            ),
          ),
        ),
      );
    }

    Widget smallButton(IconData icon, String tooltip, VoidCallback onTap) {
      return Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Icon(icon, size: 15, color: palette.muted),
          ),
        ),
      );
    }

    return Material(
      color: palette.toolbarBg,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Focus(
                  onKeyEvent: _onFindKey,
                  child: field(_findController, 'Find', focus: _findFocus,
                      onChanged: (_) {
                    _matchIndex = 0;
                    _updateMatches();
                  }),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 44,
                  child: Text(countLabel,
                      style: TextStyle(color: palette.muted, fontSize: 12)),
                ),
                smallButton(Icons.keyboard_arrow_up, 'Previous (Shift+Enter)',
                    () => _findStep(-1)),
                smallButton(Icons.keyboard_arrow_down, 'Next (Enter)',
                    () => _findStep(1)),
                smallButton(
                    _replaceVisible
                        ? Icons.expand_less
                        : Icons.find_replace_outlined,
                    'Replace',
                    () => setState(() => _replaceVisible = !_replaceVisible)),
                smallButton(Icons.close, 'Close (Esc)', _closeFind),
              ],
            ),
            if (_replaceVisible) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  field(_replaceController, 'Replace with'),
                  const SizedBox(width: 8),
                  TextButton(
                      onPressed: _replaceCurrent,
                      child: Text('Replace',
                          style: TextStyle(
                              fontSize: 12, color: palette.accent))),
                  TextButton(
                      onPressed: _replaceAll,
                      child: Text('All',
                          style: TextStyle(
                              fontSize: 12, color: palette.accent))),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBar(TracePalette palette) {
    final showWindowButtons = Platform.isWindows || Platform.isLinux;
    return Container(
      height: _kTitleBarHeight,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            palette.bg.withValues(alpha: 0.92),
            palette.bg.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 4),
          Opacity(
            opacity: 0.55,
            child: IconButton(
              tooltip: 'Sidebar (Ctrl+\\)',
              onPressed:
                  _sidebarRoot == null ? _pickSidebarRoot : _toggleSidebar,
              iconSize: 15,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.vertical_split_outlined, color: palette.muted),
            ),
          ),
          Expanded(
            child: DragToMoveArea(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTap: _toggleMaximize,
                child: Center(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: _docName,
                        style: TextStyle(
                          color: palette.fg.withValues(alpha: 0.75),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_dirty)
                        TextSpan(
                          text: ' — Edited',
                          style: TextStyle(
                            color: palette.muted,
                            fontSize: 12.5,
                          ),
                        ),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
          if (showWindowButtons) ...[
            _WindowButton(
              icon: Icons.remove,
              palette: palette,
              onPressed: () async {
                try {
                  await windowManager.minimize();
                } catch (_) {}
              },
            ),
            _WindowButton(
              icon: _isMaximized ? Icons.filter_none : Icons.crop_square,
              iconSize: _isMaximized ? 12 : 14,
              palette: palette,
              onPressed: _toggleMaximize,
            ),
            _WindowButton(
              icon: Icons.close,
              palette: palette,
              isClose: true,
              onPressed: () async {
                try {
                  await windowManager.close();
                } catch (_) {}
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEditor(TracePalette palette) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 56),
          child: Focus(
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
              style: TextStyle(
                color: palette.fg,
                fontSize: widget.settings.editorFontSize,
                height: 1.85,
                letterSpacing: 0.1,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'A quiet place to write.   ·   Ctrl+K for commands',
                hintStyle: TextStyle(color: palette.muted),
                contentPadding: const EdgeInsets.only(
                    top: _kTitleBarHeight + 14, bottom: 90),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToolbar(TracePalette palette) {
    final glyphStyle = TextStyle(
      color: palette.muted,
      fontSize: 14.5,
      fontWeight: FontWeight.w600,
      height: 1,
    );

    Widget glyphButton(String glyph, String tooltip, VoidCallback onPressed,
        {FontStyle? fontStyle, bool active = false}) {
      return Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
            child: Text(
              glyph,
              style: glyphStyle.copyWith(
                fontStyle: fontStyle,
                color: active ? palette.accent : palette.muted,
              ),
            ),
          ),
        ),
      );
    }

    Widget iconButton(IconData icon, String tooltip, VoidCallback onPressed,
        {bool active = false}) {
      return Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Icon(icon,
                size: 16, color: active ? palette.accent : palette.muted),
          ),
        ),
      );
    }

    final chars = _controller.text.length;
    final readMinutes = math.max(1, (_wordCount / 200).ceil());

    return Material(
      color: palette.toolbarBg,
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            glyphButton('H', 'Heading', _cycleHeading),
            glyphButton('B', 'Bold (Ctrl+B)', () => _wrapSelection('**')),
            glyphButton('I', 'Italic (Ctrl+I)', () => _wrapSelection('*'),
                fontStyle: FontStyle.italic),
            iconButton(Icons.format_list_bulleted, 'List', _toggleList),
            iconButton(Icons.search, 'Find (Ctrl+F)',
                () => _openFind(replace: false)),
            glyphButton(
                '#',
                'View: ${_controller.viewMode.label} — click to cycle '
                '(Ctrl+Shift+H)',
                _cycleViewMode,
                active: _controller.viewMode != MarkdownViewMode.concealed),
            iconButton(Icons.filter_center_focus, 'Focus mode (Ctrl+Shift+F)',
                _toggleFocusMode,
                active: _controller.focusMode),
            MenuAnchor(
              menuChildren: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$_wordCount words',
                          style: TextStyle(fontSize: 13, color: palette.fg)),
                      const SizedBox(height: 4),
                      Text('$chars characters',
                          style: TextStyle(fontSize: 12, color: palette.muted)),
                      Text('$readMinutes min read',
                          style: TextStyle(fontSize: 12, color: palette.muted)),
                      if (_selWordCount > 0) ...[
                        const SizedBox(height: 4),
                        Text('$_selWordCount words selected',
                            style: TextStyle(
                                fontSize: 12, color: palette.accent)),
                      ],
                    ],
                  ),
                ),
              ],
              builder: (context, controller, child) => iconButton(
                Icons.info_outline,
                'Statistics',
                () =>
                    controller.isOpen ? controller.close() : controller.open(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom caption button for the hidden-title-bar window (Windows/Linux).
class _WindowButton extends StatefulWidget {
  final IconData icon;
  final double iconSize;
  final TracePalette palette;
  final bool isClose;
  final VoidCallback onPressed;

  const _WindowButton({
    required this.icon,
    required this.palette,
    required this.onPressed,
    this.iconSize = 15,
    this.isClose = false,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  var _hovering = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final hoverBg = widget.isClose
        ? const Color(0xFFE81123)
        : palette.fg.withValues(alpha: 0.08);
    final iconColor = _hovering && widget.isClose
        ? Colors.white
        : palette.muted.withValues(alpha: _hovering ? 1 : 0.7);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: Container(
          width: 44,
          height: _kTitleBarHeight,
          color: _hovering ? hoverBg : Colors.transparent,
          child: Icon(widget.icon, size: widget.iconSize, color: iconColor),
        ),
      ),
    );
  }
}

/// Trace's hover table of contents: quiet dashes marking headings; hovering
/// reveals the full outline, clicking jumps to a heading.
class HoverToc extends StatefulWidget {
  final TracePalette palette;
  final List<(int level, String text, int offset)> headings;
  final void Function(int offset) onJump;

  const HoverToc({
    super.key,
    required this.palette,
    required this.headings,
    required this.onJump,
  });

  @override
  State<HoverToc> createState() => _HoverTocState();
}

class _HoverTocState extends State<HoverToc> {
  var _hovering = false;

  @override
  Widget build(BuildContext context) {
    if (widget.headings.isEmpty) return const SizedBox.shrink();
    final palette = widget.palette;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 160),
        switchInCurve: Curves.easeOutCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: child,
        ),
        child: _hovering ? _panel(palette) : _dashes(palette),
      ),
    );
  }

  Widget _dashes(TracePalette palette) {
    return Column(
      key: const ValueKey('dashes'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final h in widget.headings.take(12))
          Container(
            width: (18.0 - (h.$1 - 1) * 4).clamp(6.0, 18.0),
            height: 2,
            margin: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(
              color: palette.muted.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
      ],
    );
  }

  Widget _panel(TracePalette palette) {
    return Material(
      key: const ValueKey('panel'),
      color: palette.toolbarBg,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 250,
        constraints: const BoxConstraints(maxHeight: 380),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final h in widget.headings)
                InkWell(
                  onTap: () {
                    setState(() => _hovering = false);
                    widget.onJump(h.$3);
                  },
                  child: Padding(
                    padding: EdgeInsets.only(
                        left: 14.0 + (h.$1 - 1) * 12,
                        right: 14,
                        top: 5,
                        bottom: 5),
                    child: Text(
                      h.$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: palette.fg,
                        fontWeight:
                            h.$1 == 1 ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
