import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// App preferences, persisted as a small JSON file in the platform's
/// application-support directory (Trace used UserDefaults).
class AppSettings extends ChangeNotifier {
  ThemeMode themeMode = ThemeMode.system;
  String accent = 'azure';
  String viewMode = 'concealed';
  List<String> recentFiles = [];
  String? sidebarRoot;
  String? lastFile;
  int lastCaret = 0;
  bool autosave = true;
  double editorFontSize = 15.5;

  File? _file;

  static Future<AppSettings> load() async {
    final settings = AppSettings();
    try {
      final dir = await getApplicationSupportDirectory();
      settings._file = File(p.join(dir.path, 'settings.json'));
      if (settings._file!.existsSync()) {
        final data = jsonDecode(settings._file!.readAsStringSync())
            as Map<String, dynamic>;
        settings.themeMode = ThemeMode.values.firstWhere(
          (m) => m.name == data['themeMode'],
          orElse: () => ThemeMode.system,
        );
        settings.accent = data['accent'] as String? ?? 'azure';
        settings.viewMode = data['viewMode'] as String? ?? 'concealed';
        settings.recentFiles =
            (data['recentFiles'] as List?)?.cast<String>() ?? [];
        settings.sidebarRoot = data['sidebarRoot'] as String?;
        settings.lastFile = data['lastFile'] as String?;
        settings.lastCaret = data['lastCaret'] as int? ?? 0;
        settings.autosave = data['autosave'] as bool? ?? true;
        settings.editorFontSize =
            (data['editorFontSize'] as num?)?.toDouble() ?? 15.5;
      }
    } catch (_) {
      // Missing/corrupt settings are non-fatal; start with defaults.
    }
    return settings;
  }

  Future<void> _save() async {
    try {
      await _file?.writeAsString(jsonEncode({
        'themeMode': themeMode.name,
        'accent': accent,
        'viewMode': viewMode,
        'recentFiles': recentFiles,
        'sidebarRoot': sidebarRoot,
        'lastFile': lastFile,
        'lastCaret': lastCaret,
        'autosave': autosave,
        'editorFontSize': editorFontSize,
      }));
    } catch (_) {}
  }

  void setThemeMode(ThemeMode mode) {
    themeMode = mode;
    notifyListeners();
    _save();
  }

  void setAccent(String key) {
    accent = key;
    notifyListeners();
    _save();
  }

  void setViewMode(String mode) {
    viewMode = mode;
    notifyListeners();
    _save();
  }

  void setSidebarRoot(String? path) {
    sidebarRoot = path;
    notifyListeners();
    _save();
  }

  void setAutosave(bool value) {
    autosave = value;
    notifyListeners();
    _save();
  }

  void setEditorFontSize(double size) {
    editorFontSize = size.clamp(11.0, 28.0);
    notifyListeners();
    _save();
  }

  /// Remember the open document and caret so the next launch restores it.
  Future<void> setSession(String? path, int caret) async {
    lastFile = path;
    lastCaret = caret;
    await _save();
  }

  void addRecent(String path) {
    recentFiles.remove(path);
    recentFiles.insert(0, path);
    if (recentFiles.length > 10) {
      recentFiles = recentFiles.sublist(0, 10);
    }
    notifyListeners();
    _save();
  }
}
