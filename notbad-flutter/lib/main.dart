import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'editor_screen.dart';
import 'settings.dart';
import 'theme.dart';

const _kInstancePort = 47653;

/// Single-instance guard: the first launch binds a loopback port and listens
/// for file paths; later launches hand their file to it and exit, so
/// double-clicking documents reuses the existing window.
Future<bool> _becomePrimary(String? fileArg) async {
  try {
    final server =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, _kInstancePort);
    server.listen((socket) {
      socket.listen((data) {
        final path = utf8.decode(data).trim();
        if (path.isEmpty || File(path).existsSync()) {
          onExternalOpen?.call(path);
        }
        socket.destroy();
      });
    });
    return true;
  } on SocketException {
    try {
      final socket = await Socket.connect(
          InternetAddress.loopbackIPv4, _kInstancePort,
          timeout: const Duration(milliseconds: 800));
      socket.add(utf8.encode(fileArg ?? ''));
      await socket.flush();
      socket.destroy();
      return false;
    } catch (_) {
      // Port taken by something that isn't us — run standalone.
      return true;
    }
  }
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  String? fileArg;
  for (final arg in args) {
    if (File(arg).existsSync()) {
      fileArg = arg;
      break;
    }
  }
  if (!await _becomePrimary(fileArg)) {
    exit(0);
  }
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
  final initialFile = fileArg ??
      ((settings.lastFile != null && File(settings.lastFile!).existsSync())
          ? settings.lastFile
          : null);

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
