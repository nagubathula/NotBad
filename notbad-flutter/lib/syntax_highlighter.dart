import 'package:flutter/material.dart';
import 'theme.dart';

/// Lightweight, pure-Dart syntax tokenizer designed for code fences.
/// Applies tranquil, palette-aware colors that harmonize with Warm Paper
/// and Neutral Warm themes without requiring webviews or heavy runtimes.
class SyntaxHighlighter {
  static const _keywords = {
    'abstract', 'alter', 'as', 'assert', 'async', 'await', 'break', 'by',
    'case', 'catch', 'class', 'const', 'continue', 'create', 'default',
    'def', 'deferred', 'delete', 'do', 'drop', 'dynamic', 'echo', 'elif',
    'else', 'enum', 'esac', 'except', 'exit', 'export', 'extends',
    'extension', 'external', 'factory', 'false', 'fi', 'final', 'finally',
    'for', 'from', 'function', 'get', 'global', 'group', 'having', 'hide',
    'if', 'implements', 'import', 'in', 'insert', 'interface', 'is', 'join',
    'lambda', 'late', 'let', 'library', 'limit', 'mixin', 'new', 'nonlocal',
    'null', 'of', 'on', 'operator', 'order', 'part', 'pass', 'raise',
    'required', 'rethrow', 'return', 'select', 'set', 'show', 'static',
    'super', 'switch', 'sync', 'table', 'then', 'this', 'throw', 'true',
    'try', 'typedef', 'until', 'update', 'var', 'void', 'where', 'while',
    'with', 'yield', 'None', 'True', 'False',
  };

  static const _types = {
    'int', 'double', 'num', 'bool', 'String', 'List', 'Map', 'Set', 'Future',
    'Stream', 'Object', 'DateTime', 'Duration', 'Type', 'Symbol', 'Widget',
    'BuildContext', 'State', 'StatefulWidget', 'StatelessWidget', 'Color',
    'TextStyle', 'Text', 'Column', 'Row', 'Container', 'SizedBox', 'Padding',
    'Promise', 'Array', 'Boolean', 'Number', 'dict', 'list', 'str', 'float',
  };

  static final _tokenPattern = RegExp(
    r'(//.*$|#.*$|/\*.*?\*/)' // 1: single-line comment
    r'|("(?:[^"\\]|\\.)*"|' r"'(?:[^'\\]|\\.)*'|" r'`(?:[^`\\]|\\.)*`)' // 2: strings
    r'|(\b\d+(?:\.\d+)?\b)' // 3: numbers
    r'|(@[a-zA-Z_]\w*)' // 4: annotations / decorators
    r'|(\b[a-zA-Z_]\w*\b)' // 5: words (identifiers, keywords, types)
    r'|([{}()\[\],;])' // 6: punctuation
    r'|(\S+)', // 7: any other symbols
  );

  /// Highlights a single line of code within a code fence.
  static List<TextSpan> highlightLine({
    required String line,
    required String? language,
    required TracePalette palette,
    required TextStyle baseStyle,
    bool dimmed = false,
  }) {
    if (line.isEmpty) {
      return [TextSpan(text: '', style: baseStyle)];
    }

    if (dimmed) {
      return [TextSpan(text: line, style: baseStyle)];
    }

    final isDark = palette.brightness == Brightness.dark;

    // Palette-derived syntax colors:
    final commentColor = palette.muted;
    final stringColor = isDark ? const Color(0xFF7EE787) : const Color(0xFF1A7F37);
    final numberColor = isDark ? const Color(0xFF79C0FF) : const Color(0xFF0969DA);
    final keywordColor = isDark ? const Color(0xFFFF7B72) : const Color(0xFFCF222E);
    final typeColor = isDark ? const Color(0xFFFFA657) : const Color(0xFF9A6700);
    final annotationColor = palette.accent;

    final spans = <TextSpan>[];
    var lastIndex = 0;

    for (final match in _tokenPattern.allMatches(line)) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(
          text: line.substring(lastIndex, match.start),
          style: baseStyle,
        ));
      }

      final text = match.group(0)!;
      TextStyle tokenStyle = baseStyle;

      if (match.group(1) != null) {
        // Comment
        tokenStyle = baseStyle.copyWith(
          color: commentColor,
          fontStyle: FontStyle.italic,
        );
      } else if (match.group(2) != null) {
        // String
        tokenStyle = baseStyle.copyWith(color: stringColor);
      } else if (match.group(3) != null) {
        // Number
        tokenStyle = baseStyle.copyWith(color: numberColor);
      } else if (match.group(4) != null) {
        // Annotation
        tokenStyle = baseStyle.copyWith(color: annotationColor);
      } else if (match.group(5) != null) {
        // Word
        final lower = text.toLowerCase();
        if (_keywords.contains(text) || _keywords.contains(lower)) {
          tokenStyle = baseStyle.copyWith(
            color: keywordColor,
            fontWeight: FontWeight.w600,
          );
        } else if (_types.contains(text)) {
          tokenStyle = baseStyle.copyWith(
            color: typeColor,
            fontWeight: FontWeight.w500,
          );
        } else {
          tokenStyle = baseStyle;
        }
      }

      spans.add(TextSpan(text: text, style: tokenStyle));
      lastIndex = match.end;
    }

    if (lastIndex < line.length) {
      spans.add(TextSpan(
        text: line.substring(lastIndex),
        style: baseStyle,
      ));
    }

    return spans;
  }
}
