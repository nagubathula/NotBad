import 'dart:math' as math;
import 'package:flutter/material.dart';
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
