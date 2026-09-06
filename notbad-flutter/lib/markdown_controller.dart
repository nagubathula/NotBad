import 'package:flutter/material.dart';

import 'theme.dart';

const kMonoFallback = [
  'Consolas',
  'Menlo',
  'DejaVu Sans Mono',
  'monospace',
];

/// The three ways to view a document:
/// - [concealed]: font styles applied, syntax marks hidden (the line under
///   the caret still reveals its marks so editing stays predictable);
/// - [marks]: font styles applied AND all syntax marks visible;
/// - [plain]: pure markdown source, monospace, no styling.
enum MarkdownViewMode { concealed, marks, plain }

extension MarkdownViewModeLabel on MarkdownViewMode {
  String get label => switch (this) {
        MarkdownViewMode.concealed => 'Styled, Marks Hidden',
        MarkdownViewMode.marks => 'Styled with Marks',
        MarkdownViewMode.plain => 'Plain Markdown',
      };
}

/// A TextEditingController that styles Markdown as you type — the pure-Flutter
/// stand-in for Trace's CodeMirror concealment engine. Caret offsets always
/// map to the raw source: concealed marks stay in the string but render
/// transparent and near-zero-width.
class MarkdownEditingController extends TextEditingController {
  MarkdownEditingController({required TracePalette palette})
      : _palette = palette;

  TracePalette _palette;
  bool _focusMode = false;
  MarkdownViewMode _viewMode = MarkdownViewMode.concealed;

  // Per-line span cache: unchanged lines reuse their spans across rebuilds,
  // keeping large documents responsive. Keyed by line content plus every
  // flag that affects its rendering.
  final Map<String, List<InlineSpan>> _lineCache = {};

  // Literal, case-insensitive search state (find bar).
  String _searchQuery = '';
  List<int> _searchMatches = const [];
  int _searchCurrent = -1;
  String? _searchSource;

  set palette(TracePalette value) {
    if (value.brightness == _palette.brightness &&
        value.accent == _palette.accent) {
      return;
    }
    _palette = value;
    _lineCache.clear();
    notifyListeners();
  }

  bool get focusMode => _focusMode;
  set focusMode(bool value) {
    if (value == _focusMode) return;
    _focusMode = value;
    notifyListeners();
  }

  MarkdownViewMode get viewMode => _viewMode;
  set viewMode(MarkdownViewMode value) {
    if (value == _viewMode) return;
    _viewMode = value;
    _lineCache.clear();
    notifyListeners();
  }

  String get searchQuery => _searchQuery;
  List<int> get searchMatches => _searchMatches;

  /// Set (or clear) the live search. Matches are literal, case-insensitive.
  /// [current] is the character offset of the active match, painted stronger.
  void setSearch(String query, {int current = -1}) {
    if (query == _searchQuery &&
        current == _searchCurrent &&
        identical(_searchSource, text)) {
      return;
    }
    _searchQuery = query;
    _searchCurrent = current;
    _searchSource = text;
    final matches = <int>[];
    if (query.isNotEmpty) {
      final source = text.toLowerCase();
      final needle = query.toLowerCase();
      var idx = source.indexOf(needle);
      while (idx != -1) {
        matches.add(idx);
        idx = source.indexOf(needle, idx + needle.length);
      }
    }
    _searchMatches = matches;
    notifyListeners();
  }

  /// Pasted or loaded text can carry CRLF line endings; the invisible `\r`
  /// breaks every `$`-anchored line rule, so normalize to LF on any change,
  /// shifting the caret back by the number of removed characters before it.
  @override
  set value(TextEditingValue newValue) {
    final t = newValue.text;
    if (t.contains('\r')) {
      int adjust(int offset) {
        if (offset < 0) return offset;
        var removed = 0;
        final limit = offset.clamp(0, t.length);
        for (var i = 0; i < limit; i++) {
          if (t.codeUnitAt(i) == 0x0D &&
              i + 1 < t.length &&
              t.codeUnitAt(i + 1) == 0x0A) {
            removed++;
          }
        }
        return offset - removed;
      }

      newValue = TextEditingValue(
        text: t.replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
        selection: newValue.selection.copyWith(
          baseOffset: adjust(newValue.selection.baseOffset),
          extentOffset: adjust(newValue.selection.extentOffset),
        ),
        composing: TextRange.empty,
      );
    }
    super.value = newValue;
  }

  static final _headingRe = RegExp(r'^(#{1,6})(\s+)(.*)$');
  static final _fenceRe = RegExp(r'^\s*(```|~~~)');
  static final _hrRe = RegExp(r'^\s*(-{3,}|\*{3,}|_{3,})\s*$');
  static final _quoteRe = RegExp(r'^(\s*>+\s?)(.*)$');
  static final _taskRe = RegExp(r'^(\s*)([-*+])(\s+)\[([ xX])\](\s+)(.*)$');
  static final _listRe = RegExp(r'^(\s*)([-*+]|\d{1,9}[.)])(\s+)(.*)$');
  static final _inlineRe = RegExp(
    r'(\*\*\*[^*\n]+\*\*\*)'
    r'|(\*\*[^*\n]+\*\*)'
    r'|(__[^_\n]+__)'
    r'|(~~[^~\n]+~~)'
    r'|(`[^`\n]+`)'
    r'|(!?\[[^\]\n]*\]\([^)\n]*\))'
    r'|(\*[^*\s][^*\n]*\*)'
    r'|(_[^_\s][^_\n]*_)',
  );

  /// The style for syntax marks, depending on the view mode. On the caret's
  /// own line, concealed marks reappear dimmed so edits stay predictable.
  TextStyle _markStyle(TextStyle base, bool caretLine) {
    switch (_viewMode) {
      case MarkdownViewMode.marks:
        return base.copyWith(color: _palette.muted);
      case MarkdownViewMode.concealed:
        return caretLine
            ? base.copyWith(color: _palette.marks)
            : base.copyWith(color: Colors.transparent, fontSize: 0.1);
      case MarkdownViewMode.plain:
        return base;
    }
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = (style ?? const TextStyle()).copyWith(color: _palette.fg);
    final lines = text.split('\n');
    final focused = _focusMode ? _linesAround(lines, expand: true) : null;
    final caretLines = _linesAround(lines, expand: false);

    if (_viewMode == MarkdownViewMode.plain) {
      return _applySearchHighlight(_buildPlain(lines, base, focused));
    }

    if (_lineCache.length > 6000) _lineCache.clear();

    // YAML frontmatter at the top of the document renders as a quiet
    // mono block (Trace tucks it into a Properties chip).
    var frontmatterEnd = -1;
    if (lines.isNotEmpty && lines[0].trim() == '---') {
      for (var i = 1; i < lines.length && i <= 50; i++) {
        if (lines[i].trim() == '---') {
          frontmatterEnd = i;
          break;
        }
      }
    }

    final children = <InlineSpan>[];
    var inFence = false;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      var lineBase = base;
      final dimmed = focused != null && !focused.contains(i);
      if (dimmed) {
        lineBase = lineBase.copyWith(
          color: _palette.fg.withValues(alpha: 0.28),
        );
      }
      final onCaretLine = caretLines.contains(i);
      final inFrontmatter = frontmatterEnd != -1 && i <= frontmatterEnd;
      final isFenceLine = !inFrontmatter && _fenceRe.hasMatch(line);
      final fenced = isFenceLine || inFence;

      final key = '${base.fontSize}|$dimmed|$onCaretLine|$fenced|'
          '$isFenceLine|$inFrontmatter|$line';
      var spans = _lineCache[key];
      if (spans == null) {
        if (inFrontmatter) {
          spans = [
            TextSpan(
              text: line,
              style: lineBase.copyWith(
                fontFamily: 'Consolas',
                fontFamilyFallback: kMonoFallback,
                fontSize: (lineBase.fontSize ?? 16) - 2.5,
                color: dimmed ? lineBase.color : _palette.muted,
              ),
            ),
          ];
        } else if (fenced) {
          spans = [
            TextSpan(
              text: line,
              style: lineBase.copyWith(
                fontFamily: 'Consolas',
                fontFamilyFallback: kMonoFallback,
                fontSize: (lineBase.fontSize ?? 16) - 1.5,
                backgroundColor: _palette.codeBg,
                color: isFenceLine ? _palette.marks : lineBase.color,
              ),
            ),
          ];
        } else {
          spans = _styleLine(line, lineBase, dimmed, onCaretLine);
        }
        _lineCache[key] = spans;
      }
      children.addAll(spans);
      if (isFenceLine) inFence = !inFence;
      if (i < lines.length - 1) {
        // Blank lines get a taller line box — paragraph breathing room.
        final tall = line.trim().isEmpty && !fenced;
        children.add(TextSpan(
            text: '\n',
            style: tall
                ? lineBase.copyWith(height: (lineBase.height ?? 1.85) * 1.25)
                : lineBase));
      }
    }
    return _applySearchHighlight(TextSpan(style: base, children: children));
  }

  /// Overlay search-match backgrounds onto the styled span tree by walking
  /// it with running offsets and splitting leaf spans at match boundaries.
  TextSpan _applySearchHighlight(TextSpan root) {
    if (_searchMatches.isEmpty || _searchQuery.isEmpty) return root;
    final len = _searchQuery.length;
    final starts = _searchMatches;
    final matchBg = _palette.accent.withValues(alpha: 0.28);
    final currentBg = _palette.accent.withValues(alpha: 0.55);

    final out = <InlineSpan>[];
    var pos = 0;

    // Index of the last match starting at or before [abs].
    int lastStartAtOrBefore(int abs) {
      var lo = 0, hi = starts.length - 1, ans = -1;
      while (lo <= hi) {
        final mid = (lo + hi) >> 1;
        if (starts[mid] <= abs) {
          ans = mid;
          lo = mid + 1;
        } else {
          hi = mid - 1;
        }
      }
      return ans;
    }

    void walk(InlineSpan span, TextStyle? inherited) {
      if (span is! TextSpan) return;
      final style = inherited?.merge(span.style) ?? span.style;
      final t = span.text;
      if (t != null && t.isNotEmpty) {
        var i = 0;
        while (i < t.length) {
          final abs = pos + i;
          final mi = lastStartAtOrBefore(abs);
          final inMatch = mi >= 0 && abs < starts[mi] + len;
          int segEnd;
          if (inMatch) {
            segEnd = (starts[mi] + len - pos).clamp(i + 1, t.length);
          } else {
            final nextStart =
                mi + 1 < starts.length ? starts[mi + 1] : 1 << 30;
            segEnd = (nextStart - pos).clamp(i + 1, t.length);
          }
          var segStyle = style;
          if (inMatch) {
            segStyle = (style ?? const TextStyle()).copyWith(
                backgroundColor:
                    starts[mi] == _searchCurrent ? currentBg : matchBg);
          }
          out.add(TextSpan(text: t.substring(i, segEnd), style: segStyle));
          i = segEnd;
        }
        pos += t.length;
      }
      final kids = span.children;
      if (kids != null) {
        for (final c in kids) {
          walk(c, style);
        }
      }
    }

    walk(root, null);
    return TextSpan(children: out);
  }

  TextSpan _buildPlain(
      List<String> lines, TextStyle base, Set<int>? focused) {
    final mono = base.copyWith(
      fontFamily: 'Consolas',
      fontFamilyFallback: kMonoFallback,
      fontSize: (base.fontSize ?? 16) - 1,
    );
    final children = <InlineSpan>[];
    for (var i = 0; i < lines.length; i++) {
      final dimmed = focused != null && !focused.contains(i);
      final style = dimmed
          ? mono.copyWith(color: _palette.fg.withValues(alpha: 0.28))
          : mono;
      children.add(TextSpan(
          text: i < lines.length - 1 ? '${lines[i]}\n' : lines[i],
          style: style));
    }
    return TextSpan(style: mono, children: children);
  }

  List<InlineSpan> _styleLine(
      String line, TextStyle base, bool dimmed, bool onCaretLine) {
    final marks = _markStyle(base, onCaretLine);

    final heading = _headingRe.firstMatch(line);
    if (heading != null) {
      final level = heading.group(1)!.length;
      final size = base.fontSize ?? 16;
      final headingStyle = base.copyWith(
        fontWeight: FontWeight.w700,
        fontSize: switch (level) {
          1 => size * 1.6,
          2 => size * 1.35,
          3 => size * 1.15,
          _ => size,
        },
      );
      return [
        TextSpan(
          text: heading.group(1)! + heading.group(2)!,
          style: _viewMode == MarkdownViewMode.concealed && !onCaretLine
              ? marks
              : headingStyle.copyWith(color: marks.color),
        ),
        ..._inlineSpans(heading.group(3)!, headingStyle, marks),
      ];
    }

    if (_hrRe.hasMatch(line)) {
      // The rule itself is the visual — always visible, just dimmed.
      return [
        TextSpan(text: line, style: base.copyWith(color: _palette.marks))
      ];
    }

    final quote = _quoteRe.firstMatch(line);
    if (quote != null && quote.group(1)!.trimLeft().startsWith('>')) {
      final quoteStyle = base.copyWith(
        fontStyle: FontStyle.italic,
        color: dimmed ? base.color : _palette.muted,
      );
      return [
        // The `>` doubles as the quote indicator — keep it visible.
        TextSpan(
          text: quote.group(1),
          style: base.copyWith(color: _accentOr(base, dimmed)),
        ),
        ..._inlineSpans(quote.group(2)!, quoteStyle, marks),
      ];
    }

    final task = _taskRe.firstMatch(line);
    if (task != null) {
      final done = task.group(4)!.toLowerCase() == 'x';
      final textStyle = done
          ? base.copyWith(
              decoration: TextDecoration.lineThrough,
              color: dimmed ? base.color : _palette.muted,
            )
          : base;
      return [
        TextSpan(
          text: task.group(1)! + task.group(2)! + task.group(3)!,
          style: base.copyWith(color: _accentOr(base, dimmed)),
        ),
        TextSpan(
          text: '[${task.group(4)}]',
          style: base.copyWith(
            fontFamily: 'Consolas',
            fontFamilyFallback: kMonoFallback,
            color: _accentOr(base, dimmed),
          ),
        ),
        TextSpan(text: task.group(5), style: base),
        ..._inlineSpans(task.group(6)!, textStyle, marks),
      ];
    }

    final list = _listRe.firstMatch(line);
    if (list != null) {
      return [
        TextSpan(
          text: list.group(1)! + list.group(2)! + list.group(3)!,
          style: base.copyWith(
            color: _accentOr(base, dimmed),
            fontWeight: FontWeight.w600,
          ),
        ),
        ..._inlineSpans(list.group(4)!, base, marks),
      ];
    }

    return _inlineSpans(line, base, marks);
  }

  Color _accentOr(TextStyle base, bool dimmed) =>
      dimmed ? (base.color ?? _palette.fg) : _palette.accent;

  List<InlineSpan> _inlineSpans(String s, TextStyle base, TextStyle marks) {
    if (s.isEmpty) return [TextSpan(text: s, style: base)];
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _inlineRe.allMatches(s)) {
      if (m.start > last) {
        spans.add(TextSpan(text: s.substring(last, m.start), style: base));
      }
      spans.addAll(_inlineToken(m.group(0)!, base, marks));
      last = m.end;
    }
    if (last < s.length) {
      spans.add(TextSpan(text: s.substring(last), style: base));
    }
    return spans;
  }

  List<InlineSpan> _inlineToken(String t, TextStyle base, TextStyle marks) {
    TextSpan wrap(int markLen, TextStyle inner) => TextSpan(children: [
          TextSpan(
              text: t.substring(0, markLen),
              style: marks.copyWith(fontStyle: inner.fontStyle)),
          TextSpan(
              text: t.substring(markLen, t.length - markLen), style: inner),
          TextSpan(
              text: t.substring(t.length - markLen),
              style: marks.copyWith(fontStyle: inner.fontStyle)),
        ]);

    if (t.startsWith('***')) {
      return [
        wrap(
            3,
            base.copyWith(
                fontWeight: FontWeight.w700, fontStyle: FontStyle.italic))
      ];
    }
    if (t.startsWith('**') || t.startsWith('__')) {
      return [wrap(2, base.copyWith(fontWeight: FontWeight.w700))];
    }
    if (t.startsWith('~~')) {
      return [wrap(2, base.copyWith(decoration: TextDecoration.lineThrough))];
    }
    if (t.startsWith('`')) {
      return [
        TextSpan(text: '`', style: marks),
        TextSpan(
          text: t.substring(1, t.length - 1),
          style: base.copyWith(
            fontFamily: 'Consolas',
            fontFamilyFallback: kMonoFallback,
            fontSize: (base.fontSize ?? 16) - 1.5,
            backgroundColor: _palette.codeBg,
          ),
        ),
        TextSpan(text: '`', style: marks),
      ];
    }
    if (t.startsWith('[') || t.startsWith('![')) {
      final bracket = t.indexOf(']');
      final prefixLen = t.startsWith('![') ? 2 : 1;
      return [
        TextSpan(text: t.substring(0, prefixLen), style: marks),
        TextSpan(
          text: t.substring(prefixLen, bracket),
          style: base.copyWith(
            color: _palette.accent,
            decoration: TextDecoration.underline,
            decorationColor: _palette.accent.withValues(alpha: 0.4),
          ),
        ),
        TextSpan(text: t.substring(bracket), style: marks),
      ];
    }
    if (t.startsWith('*') || t.startsWith('_')) {
      return [wrap(1, base.copyWith(fontStyle: FontStyle.italic))];
    }
    return [TextSpan(text: t, style: base)];
  }

  /// Lines around the caret. With [expand] true, grows to the whole paragraph
  /// (focus mode); otherwise just the caret's line (mark reveal).
  Set<int> _linesAround(List<String> lines, {required bool expand}) {
    var offset = selection.isValid ? selection.start : 0;
    if (offset > text.length) offset = text.length;

    var caretLine = lines.length - 1;
    var run = 0;
    for (var i = 0; i < lines.length; i++) {
      if (offset <= run + lines[i].length) {
        caretLine = i;
        break;
      }
      run += lines[i].length + 1;
    }
    if (!expand) return {caretLine};

    var start = caretLine;
    while (start > 0 && lines[start - 1].trim().isNotEmpty) {
      start--;
    }
    var end = caretLine;
    while (end < lines.length - 1 && lines[end + 1].trim().isNotEmpty) {
      end++;
    }
    return {for (var i = start; i <= end; i++) i};
  }
}
