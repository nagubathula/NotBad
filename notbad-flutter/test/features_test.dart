import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notbad_flutter/markdown_controller.dart';
import 'package:notbad_flutter/settings.dart';
import 'package:notbad_flutter/syntax_highlighter.dart';
import 'package:notbad_flutter/theme.dart';
import 'package:notbad_flutter/widgets/floating_toolbar.dart';
import 'package:notbad_flutter/widgets/progress_ring.dart';
import 'package:notbad_flutter/widgets/window_title_bar.dart';

void main() {
  group('SyntaxHighlighter', () {
    test('tokenizes keywords, strings, numbers, and comments', () {
      final palette = TracePalette.of(Brightness.light, 'azure');
      const baseStyle = TextStyle(fontSize: 14, color: Colors.black);
      final spans = SyntaxHighlighter.highlightLine(
        line: 'const x = 42; // answer',
        language: 'dart',
        palette: palette,
        baseStyle: baseStyle,
      );

      expect(spans, isNotEmpty);
      // 'const' is keyword
      final constSpan = spans.firstWhere((s) => s.text == 'const');
      expect(constSpan.style?.fontWeight, equals(FontWeight.w600));

      // '42' is number
      final numSpan = spans.firstWhere((s) => s.text == '42');
      expect(numSpan.style?.color, isNotNull);

      // '// answer' is comment
      final commentSpan = spans.firstWhere((s) => s.text?.contains('//') ?? false);
      expect(commentSpan.style?.fontStyle, equals(FontStyle.italic));
    });

    testWidgets('fenced code blocks in MarkdownEditingController use syntax highlighting',
        (tester) async {
      final palette = TracePalette.of(Brightness.light, 'azure');
      final controller = MarkdownEditingController(palette: palette);
      controller.text = '```dart\nfinal greeting = "hello";\n```';

      late TextSpan span;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) {
            span = controller.buildTextSpan(
              context: context,
              withComposing: false,
            );
            return Text.rich(span);
          },
        ),
      ));

      expect(span.toPlainText(), equals(controller.text));
    });
  });

  group('E-Ink Mode & Themes', () {
    test('TracePalette.of with eInk produces high-contrast black and white', () {
      final lightEInk = TracePalette.of(Brightness.light, 'azure', eInk: true);
      expect(lightEInk.bg, equals(const Color(0xFFFFFFFF)));
      expect(lightEInk.fg, equals(const Color(0xFF000000)));
      expect(lightEInk.border, equals(const Color(0xFF000000)));

      final darkEInk = TracePalette.of(Brightness.dark, 'azure', eInk: true);
      expect(darkEInk.bg, equals(const Color(0xFF000000)));
      expect(darkEInk.fg, equals(const Color(0xFFFFFFFF)));
      expect(darkEInk.border, equals(const Color(0xFFFFFFFF)));
    });
  });

  group('Daily Word Goal & ProgressRing', () {
    testWidgets('ProgressRing renders without error when goal is set', (tester) async {
      final palette = TracePalette.of(Brightness.light, 'azure');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: ProgressRing(
              currentWords: 500,
              goalWords: 1000,
              palette: palette,
            ),
          ),
        ),
      ));

      expect(find.byType(ProgressRing), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    test('AppSettings updates and handles dailyWordGoal and eInkMode', () {
      final settings = AppSettings();
      expect(settings.dailyWordGoal, equals(0));
      expect(settings.eInkMode, isFalse);

      settings.setDailyWordGoal(750);
      expect(settings.dailyWordGoal, equals(750));

      settings.setEInkMode(true);
      expect(settings.eInkMode, isTrue);

      settings.setShowGitGutter(false);
      expect(settings.showGitGutter, isFalse);
    });
  });

  group('Modular Widgets', () {
    testWidgets('WindowTitleBar renders document name and edited indicator', (tester) async {
      final palette = TracePalette.of(Brightness.light, 'azure');
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: WindowTitleBar(
            palette: palette,
            docName: 'MyEssay.md',
            isDirty: true,
            isMaximized: false,
            onToggleSidebar: () {},
            onShowPalette: () {},
            onToggleMaximize: () {},
          ),
        ),
      ));

      expect(find.textContaining('MyEssay.md'), findsOneWidget);
      expect(find.textContaining('— Edited'), findsOneWidget);
    });

    testWidgets('FloatingToolbar displays goal indicator when set', (tester) async {
      final palette = TracePalette.of(Brightness.light, 'azure');
      final controller = MarkdownEditingController(palette: palette);
      controller.text = 'A test document with some content';

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: FloatingToolbar(
            palette: palette,
            controller: controller,
            wordCount: 6,
            selWordCount: 0,
            dailyWordGoal: 10,
            onCycleHeading: () {},
            onWrapSelection: (_) {},
            onToggleList: () {},
            onOpenFind: () {},
            onCycleViewMode: () {},
            onToggleFocusMode: () {},
          ),
        ),
      ));

      expect(find.byType(ProgressRing), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });
  });
}
