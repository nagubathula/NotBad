import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../theme.dart';

const kTitleBarHeight = 36.0;

/// Desktop window title bar with drag-to-move support, document name,
/// quick action buttons (Sidebar, Command Palette), and window controls (Min/Max/Close).
class WindowTitleBar extends StatelessWidget {
  final TracePalette palette;
  final String docName;
  final bool isDirty;
  final bool isMaximized;
  final VoidCallback onToggleSidebar;
  final VoidCallback onShowPalette;
  final VoidCallback onToggleMaximize;

  const WindowTitleBar({
    super.key,
    required this.palette,
    required this.docName,
    required this.isDirty,
    required this.isMaximized,
    required this.onToggleSidebar,
    required this.onShowPalette,
    required this.onToggleMaximize,
  });

  @override
  Widget build(BuildContext context) {
    final showWindowButtons = Platform.isWindows || Platform.isLinux;
    return Container(
      height: kTitleBarHeight,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            palette.bg.withValues(alpha: 0.92),
            palette.bg.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 4),
          Opacity(
            opacity: 0.55,
            child: IconButton(
              tooltip: 'Sidebar (Ctrl+\\)',
              onPressed: onToggleSidebar,
              iconSize: 15,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.vertical_split_outlined, color: palette.muted),
            ),
          ),
          Expanded(
            child: DragToMoveArea(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTap: onToggleMaximize,
                child: Center(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: docName,
                        style: TextStyle(
                          color: palette.fg.withValues(alpha: 0.75),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (isDirty)
                        TextSpan(
                          text: ' — Edited',
                          style: TextStyle(
                            color: palette.muted,
                            fontSize: 12.5,
                          ),
                        ),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
          Opacity(
            opacity: 0.55,
            child: IconButton(
              tooltip: 'Commands (Ctrl+K)',
              onPressed: onShowPalette,
              iconSize: 15,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.keyboard_command_key, color: palette.muted),
            ),
          ),
          const SizedBox(width: 6),
          if (showWindowButtons) ...[
            WindowButton(
              icon: Icons.remove,
              label: 'Minimize',
              palette: palette,
              onPressed: () async {
                try {
                  await windowManager.minimize();
                } catch (_) {}
              },
            ),
            WindowButton(
              icon: isMaximized ? Icons.filter_none : Icons.crop_square,
              iconSize: isMaximized ? 12 : 14,
              label: isMaximized ? 'Restore' : 'Maximize',
              palette: palette,
              onPressed: onToggleMaximize,
            ),
            WindowButton(
              icon: Icons.close,
              label: 'Close',
              palette: palette,
              isClose: true,
              onPressed: () async {
                try {
                  await windowManager.close();
                } catch (_) {}
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// Custom caption button for the hidden-title-bar window (Windows/Linux).
class WindowButton extends StatefulWidget {
  final IconData icon;
  final double iconSize;
  final String label;
  final TracePalette palette;
  final bool isClose;
  final VoidCallback onPressed;

  const WindowButton({
    super.key,
    required this.icon,
    required this.label,
    required this.palette,
    required this.onPressed,
    this.iconSize = 15,
    this.isClose = false,
  });

  @override
  State<WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<WindowButton> {
  var _hovering = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final hoverBg = widget.isClose
        ? const Color(0xFFE81123)
        : palette.fg.withValues(alpha: 0.08);
    final iconColor = _hovering && widget.isClose
        ? Colors.white
        : palette.muted.withValues(alpha: _hovering ? 1 : 0.7);
    return Tooltip(
      message: widget.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Container(
            width: 44,
            height: kTitleBarHeight,
            color: _hovering ? hoverBg : Colors.transparent,
            child: Icon(widget.icon, size: widget.iconSize, color: iconColor),
          ),
        ),
      ),
    );
  }
}
