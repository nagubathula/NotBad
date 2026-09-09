import 'package:flutter/material.dart';
import '../theme.dart';

/// Floating Find & Replace overlay panel.
class FindReplaceBar extends StatelessWidget {
  final TracePalette palette;
  final TextEditingController findController;
  final TextEditingController replaceController;
  final FocusNode findFocus;
  final bool replaceVisible;
  final int matchIndex;
  final int matchCount;
  final ValueChanged<String> onFindChanged;
  final void Function(int delta) onFindStep;
  final VoidCallback onToggleReplace;
  final VoidCallback onClose;
  final VoidCallback onReplaceCurrent;
  final VoidCallback onReplaceAll;
  final KeyEventResult Function(FocusNode, KeyEvent)? onFindKey;

  const FindReplaceBar({
    super.key,
    required this.palette,
    required this.findController,
    required this.replaceController,
    required this.findFocus,
    required this.replaceVisible,
    required this.matchIndex,
    required this.matchCount,
    required this.onFindChanged,
    required this.onFindStep,
    required this.onToggleReplace,
    required this.onClose,
    required this.onReplaceCurrent,
    required this.onReplaceAll,
    this.onFindKey,
  });

  @override
  Widget build(BuildContext context) {
    final countLabel = matchCount == 0
        ? (findController.text.isEmpty ? '' : '0/0')
        : '${matchIndex + 1}/$matchCount';

    Widget field(TextEditingController controller, String hint,
        {FocusNode? focus, void Function(String)? onChanged}) {
      return SizedBox(
        width: 190,
        height: 28,
        child: TextField(
          controller: controller,
          focusNode: focus,
          onChanged: onChanged,
          style: TextStyle(color: palette.fg, fontSize: 13),
          cursorColor: palette.accent,
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: TextStyle(color: palette.muted, fontSize: 13),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            filled: true,
            fillColor: palette.bg.withValues(alpha: 0.6),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: palette.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: palette.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: palette.accent),
            ),
          ),
        ),
      );
    }

    Widget smallButton(IconData icon, String tooltip, VoidCallback onTap) {
      return Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Icon(icon, size: 15, color: palette.muted),
          ),
        ),
      );
    }

    return Material(
      color: palette.toolbarBg,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Focus(
                  onKeyEvent: onFindKey,
                  child: field(
                    findController,
                    'Find',
                    focus: findFocus,
                    onChanged: onFindChanged,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 44,
                  child: Text(countLabel,
                      style: TextStyle(color: palette.muted, fontSize: 12)),
                ),
                smallButton(Icons.keyboard_arrow_up, 'Previous (Shift+Enter)',
                    () => onFindStep(-1)),
                smallButton(Icons.keyboard_arrow_down, 'Next (Enter)',
                    () => onFindStep(1)),
                smallButton(
                  replaceVisible
                      ? Icons.expand_less
                      : Icons.find_replace_outlined,
                  'Replace',
                  onToggleReplace,
                ),
                smallButton(Icons.close, 'Close (Esc)', onClose),
              ],
            ),
            if (replaceVisible) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  field(replaceController, 'Replace with'),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: onReplaceCurrent,
                    child: Text('Replace',
                        style: TextStyle(fontSize: 12, color: palette.accent)),
                  ),
                  TextButton(
                    onPressed: onReplaceAll,
                    child: Text('All',
                        style: TextStyle(fontSize: 12, color: palette.accent)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
