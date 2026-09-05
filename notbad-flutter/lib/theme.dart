import 'package:flutter/material.dart';

/// Accent colors ported from Trace: Amber, Crimson, Fern, Teal, Azure,
/// Graphite — each tuned separately for light and dark appearances.
class Accent {
  final String name;
  final Color light;
  final Color dark;
  const Accent(this.name, this.light, this.dark);

  Color forBrightness(Brightness b) => b == Brightness.light ? light : dark;
}

const Map<String, Accent> kAccents = {
  'amber': Accent('Amber', Color(0xFF9A6700), Color(0xFFD4A72C)),
  'crimson': Accent('Crimson', Color(0xFFCF222E), Color(0xFFF47067)),
  'fern': Accent('Fern', Color(0xFF1A7F37), Color(0xFF57AB5A)),
  'teal': Accent('Teal', Color(0xFF0F766E), Color(0xFF2DD4BF)),
  'azure': Accent('Azure', Color(0xFF0969DA), Color(0xFF4493F8)),
  'graphite': Accent('Graphite', Color(0xFF57606A), Color(0xFF8B949E)),
};

/// Trace's actual look: a warm paper tone in light, a neutral warm dark —
/// not pure white, not GitHub's blue-black.
class TracePalette {
  final Brightness brightness;
  final Color bg;
  final Color sidebarBg;
  final Color fg;
  final Color muted;
  final Color marks; // concealed syntax marks
  final Color codeBg;
  final Color border;
  final Color toolbarBg;
  final Color accent;

  const TracePalette({
    required this.brightness,
    required this.bg,
    required this.sidebarBg,
    required this.fg,
    required this.muted,
    required this.marks,
    required this.codeBg,
    required this.border,
    required this.toolbarBg,
    required this.accent,
  });

  factory TracePalette.of(Brightness brightness, String accentKey) {
    final accent =
        (kAccents[accentKey] ?? kAccents['azure']!).forBrightness(brightness);
    if (brightness == Brightness.light) {
      return TracePalette(
        brightness: brightness,
        bg: const Color(0xFFF7F6F3),
        sidebarBg: const Color(0xFFEFEDE9),
        fg: const Color(0xFF2C2C2B),
        muted: const Color(0xFF8F8E8A),
        marks: const Color(0xFF2C2C2B).withValues(alpha: 0.25),
        codeBg: const Color(0xFFEBEAE6),
        border: const Color(0xFFE2E1DD),
        toolbarBg: const Color(0xFFFFFFFF),
        accent: accent,
      );
    }
    return TracePalette(
      brightness: brightness,
      bg: const Color(0xFF2D2D2D),
      sidebarBg: const Color(0xFF252525),
      fg: const Color(0xFFE6E5E2),
      muted: const Color(0xFF98978F),
      marks: const Color(0xFFE6E5E2).withValues(alpha: 0.28),
      codeBg: const Color(0xFF383838),
      border: const Color(0xFF454545),
      toolbarBg: const Color(0xFF3A3A3A),
      accent: accent,
    );
  }
}

ThemeData buildTheme(Brightness brightness, String accentKey) {
  final palette = TracePalette.of(brightness, accentKey);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: palette.accent,
      brightness: brightness,
      surface: palette.bg,
    ),
    scaffoldBackgroundColor: palette.bg,
    dividerColor: palette.border,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: palette.accent,
      selectionColor: palette.accent.withValues(alpha: 0.25),
      selectionHandleColor: palette.accent,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(3),
      thumbColor:
          WidgetStatePropertyAll(palette.muted.withValues(alpha: 0.35)),
      crossAxisMargin: 2,
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 600),
      textStyle: TextStyle(
        fontSize: 12,
        color: brightness == Brightness.light ? Colors.white : Colors.black,
      ),
    ),
  );
}
