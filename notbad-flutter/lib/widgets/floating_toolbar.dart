import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../input_methods/indic_engine.dart';
import '../markdown_controller.dart';
import '../theme.dart';
import 'progress_ring.dart';

/// Receding floating pill toolbar with formatting actions, view mode toggle,
/// focus mode toggle, and writing metrics / goal progress popover.
class FloatingToolbar extends StatelessWidget {
  final TracePalette palette;
  final MarkdownEditingController controller;
  final int wordCount;
  final int selWordCount;
  final int dailyWordGoal;
  final InputLanguage currentLanguage;
  final ValueChanged<InputLanguage>? onSelectLanguage;
  final VoidCallback? onToggleLanguage;
  final VoidCallback? onShowKeyboardReference;
  final VoidCallback onCycleHeading;
  final void Function(String mark) onWrapSelection;
  final VoidCallback onToggleList;
  final VoidCallback onOpenFind;
  final VoidCallback onCycleViewMode;
  final VoidCallback onToggleFocusMode;

  const FloatingToolbar({
    super.key,
    required this.palette,
    required this.controller,
    required this.wordCount,
    required this.selWordCount,
    required this.dailyWordGoal,
    this.currentLanguage = InputLanguage.english,
    this.onSelectLanguage,
    this.onToggleLanguage,
    this.onShowKeyboardReference,
    required this.onCycleHeading,
    required this.onWrapSelection,
    required this.onToggleList,
    required this.onOpenFind,
    required this.onCycleViewMode,
    required this.onToggleFocusMode,
  });

  @override
  Widget build(BuildContext context) {
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

    final chars = controller.text.length;
    final readMinutes = math.max(1, (wordCount / 200).ceil());

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
            glyphButton('H', 'Heading', onCycleHeading),
            glyphButton('B', 'Bold (Ctrl+B)', () => onWrapSelection('**')),
            glyphButton('I', 'Italic (Ctrl+I)', () => onWrapSelection('*'),
                fontStyle: FontStyle.italic),
            iconButton(Icons.format_list_bulleted, 'List', onToggleList),
            iconButton(Icons.search, 'Find (Ctrl+F)', onOpenFind),
            glyphButton(
                '#',
                'View: ${controller.viewMode.label} — click to cycle '
                '(Ctrl+Shift+H)',
                onCycleViewMode,
                active: controller.viewMode != MarkdownViewMode.concealed),
            iconButton(Icons.filter_center_focus, 'Focus mode (Ctrl+Shift+F)',
                onToggleFocusMode,
                active: controller.focusMode),
            MenuAnchor(
              menuChildren: [
                for (final lang in InputLanguage.values)
                  MenuItemButton(
                    onPressed: onSelectLanguage != null
                        ? () => onSelectLanguage!(lang)
                        : null,
                    leadingIcon: Icon(
                      lang == currentLanguage
                          ? Icons.check
                          : Icons.radio_button_unchecked,
                      size: 14,
                      color: lang == currentLanguage
                          ? palette.accent
                          : palette.muted,
                    ),
                    child: Text(
                      '${lang.badge}   ${lang.label}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: lang == currentLanguage
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: lang == currentLanguage
                            ? palette.accent
                            : palette.fg,
                      ),
                    ),
                  ),
                const PopupMenuDivider(),
                MenuItemButton(
                  onPressed: onShowKeyboardReference,
                  leadingIcon: Icon(
                    Icons.keyboard_alt_outlined,
                    size: 14,
                    color: palette.accent,
                  ),
                  child: Text(
                    'View Anu Keyboard Chart…',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: palette.fg,
                    ),
                  ),
                ),
              ],
              builder: (context, menuController, child) {
                final isIndic = currentLanguage != InputLanguage.english;
                return Tooltip(
                  message:
                      'Input: ${currentLanguage.label}\nClick badge to toggle · Arrow for menu (Ctrl+M)',
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isIndic
                            ? palette.accent.withValues(alpha: 0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: isIndic
                              ? palette.accent
                              : palette.muted.withValues(alpha: 0.35),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InkWell(
                            borderRadius: const BorderRadius.horizontal(
                                left: Radius.circular(5)),
                            onTap: onToggleLanguage,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 2),
                              child: Text(
                                currentLanguage.badge,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color:
                                      isIndic ? palette.accent : palette.muted,
                                  height: 1.1,
                                ),
                              ),
                            ),
                          ),
                          InkWell(
                            borderRadius: const BorderRadius.horizontal(
                                right: Radius.circular(5)),
                            onTap: () => menuController.isOpen
                                ? menuController.close()
                                : menuController.open(),
                            child: Padding(
                              padding: const EdgeInsets.only(
                                  right: 2, top: 2, bottom: 2),
                              child: Icon(
                                Icons.arrow_drop_down,
                                size: 13,
                                color: isIndic ? palette.accent : palette.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            if (dailyWordGoal > 0) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ProgressRing(
                  currentWords: wordCount,
                  goalWords: dailyWordGoal,
                  palette: palette,
                  size: 16,
                  strokeWidth: 2.0,
                ),
              ),
            ],
            MenuAnchor(
              menuChildren: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$wordCount words',
                          style: TextStyle(fontSize: 13, color: palette.fg)),
                      const SizedBox(height: 4),
                      Text('$chars characters',
                          style: TextStyle(fontSize: 12, color: palette.muted)),
                      Text('$readMinutes min read',
                          style: TextStyle(fontSize: 12, color: palette.muted)),
                      if (selWordCount > 0) ...[
                        const SizedBox(height: 4),
                        Text('$selWordCount words selected',
                            style: TextStyle(
                                fontSize: 12, color: palette.accent)),
                      ],
                      if (dailyWordGoal > 0) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ProgressRing(
                              currentWords: wordCount,
                              goalWords: dailyWordGoal,
                              palette: palette,
                              size: 18,
                              strokeWidth: 2.2,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Goal: $wordCount / $dailyWordGoal (${(wordCount / dailyWordGoal * 100).clamp(0, 100).toInt()}%)',
                              style: TextStyle(
                                fontSize: 12,
                                color: wordCount >= dailyWordGoal
                                    ? const Color(0xFF1A7F37)
                                    : palette.accent,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              builder: (context, menuController, child) => iconButton(
                Icons.info_outline,
                'Statistics',
                () => menuController.isOpen
                    ? menuController.close()
                    : menuController.open(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
