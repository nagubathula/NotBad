import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notbad_flutter/main.dart';
import 'package:notbad_flutter/markdown_controller.dart';
import 'package:notbad_flutter/settings.dart';
import 'package:notbad_flutter/theme.dart';

void main() {
  testWidgets('app builds and shows the editor', (tester) async {
    await tester.pumpWidget(NotBadApp(settings: AppSettings()));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('statistics popover shows the word count', (tester) async {
    await tester.pumpWidget(NotBadApp(settings: AppSettings()));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField), '# Hello world\n\nSome **bold** text.');
    await tester.pumpAndSettle();
    // Typing recedes the toolbar; mouse movement brings it back.
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.byType(TextField)));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();
    expect(find.textContaining('5 words'), findsOneWidget);
  });

  testWidgets('welcome screen shows on a fresh launch and clears on typing',
      (tester) async {
    await tester.pumpWidget(NotBadApp(settings: AppSettings()));
    await tester.pumpAndSettle();
    expect(find.text('NotBad'), findsOneWidget);
    expect(find.text('New Document'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pumpAndSettle();
    expect(find.text('New Document'), findsNothing);
  });

  testWidgets('all three view modes render without altering text',
      (tester) async {
    await tester.pumpWidget(NotBadApp(settings: AppSettings()));
    await tester.pumpAndSettle();
    const source =
        '---\ntitle: test\n---\n# Hi\n\n**bold** `c` [l](u)\n- item';
    await tester.enterText(find.byType(TextField), source);
    await tester.pumpAndSettle();
    final controller = tester.widget<TextField>(find.byType(TextField)).controller
        as MarkdownEditingController;
    for (final mode in MarkdownViewMode.values) {
      controller.viewMode = mode;
      await tester.pumpAndSettle();
      expect(controller.text, source, reason: 'mode $mode changed the text');
    }
  });

  test('pasted CRLF text is normalized to LF with caret adjusted', () {
    final controller = MarkdownEditingController(
        palette: TracePalette.of(Brightness.light, 'azure'));
    controller.value = const TextEditingValue(
      text: '# Title\r\n\r\n- item\r\nlast',
      selection: TextSelection.collapsed(offset: 20), // end of pasted text
    );
    expect(controller.text, '# Title\n\n- item\nlast');
    expect(controller.text.contains('\r'), isFalse);
    expect(controller.selection.baseOffset, 17); // 3 removed \r before caret
  });

  testWidgets('Enter continues a list; Enter on empty item exits it',
      (tester) async {
    await tester.pumpWidget(NotBadApp(settings: AppSettings()));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '- item');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    final controller =
        tester.widget<TextField>(find.byType(TextField)).controller!;
    expect(controller.text, '- item\n- ');
    // Enter again on the now-empty item exits the list.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.text, '- item\n');
  });

  test('search finds case-insensitive literal matches', () {
    final controller = MarkdownEditingController(
        palette: TracePalette.of(Brightness.light, 'azure'));
    controller.text = 'Foo bar foo';
    controller.setSearch('foo');
    expect(controller.searchMatches, [0, 8]);
    controller.setSearch('');
    expect(controller.searchMatches, isEmpty);
  });

  test('controller styles markdown without altering text', () {
    final controller = MarkdownEditingController(
        palette: TracePalette.of(Brightness.light, 'azure'));
    const source = '# Title\n\n- item **bold** `code` [link](url)\n> quote';
    controller.text = source;
    expect(controller.text, source);
  });
}
