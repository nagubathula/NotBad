import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'editor_screen.dart';
import 'settings.dart';
import 'theme.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await windowManager.ensureInitialized();
    windowManager.waitUntilReadyToShow(
      const WindowOptions(
        title: 'Untitled',
        size: Size(1100, 760),
        minimumSize: Size(480, 360),
        center: true,
        titleBarStyle: TitleBarStyle.hidden,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  } catch (_) {
    // Window management unavailable (e.g. tests); continue without it.
  }
  final settings = await AppSettings.load();

  // A file passed on the command line ("Open with…" / double-click) wins;
  // otherwise restore the previous session's document.
  String? initialFile;
  for (final arg in args) {
    if (File(arg).existsSync()) {
      initialFile = arg;
      break;
    }
  }
  initialFile ??= (settings.lastFile != null &&
          File(settings.lastFile!).existsSync())
      ? settings.lastFile
      : null;

  runApp(NotBadApp(settings: settings, initialFile: initialFile));
}

/// NotBad — a Flutter port of Trace (a MarkEdit-based Markdown writer),
/// re-implemented natively for Windows, macOS, and Linux.
class NotBadApp extends StatelessWidget {
  final AppSettings settings;
  final String? initialFile;
  const NotBadApp({super.key, required this.settings, this.initialFile});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        title: 'NotBad',
        debugShowCheckedModeBanner: false,
        themeMode: settings.themeMode,
        theme: buildTheme(Brightness.light, settings.accent),
        darkTheme: buildTheme(Brightness.dark, settings.accent),
        home: EditorScreen(settings: settings, initialFile: initialFile),
      ),
    );
  }
}
