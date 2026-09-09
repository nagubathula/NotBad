import 'package:flutter/material.dart';
import '../theme.dart';

/// Hover table of contents: ambient dashes at top-left of the writing canvas
/// that expand on hover into an outline list with click-to-jump navigation.
class HoverToc extends StatefulWidget {
  final TracePalette palette;
  final List<(int level, String text, int offset)> headings;
  final void Function(int offset) onJump;

  const HoverToc({
    super.key,
    required this.palette,
    required this.headings,
    required this.onJump,
  });

  @override
  State<HoverToc> createState() => _HoverTocState();
}

class _HoverTocState extends State<HoverToc> {
  var _hovering = false;

  @override
  Widget build(BuildContext context) {
    if (widget.headings.isEmpty) return const SizedBox.shrink();
    final palette = widget.palette;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 160),
        switchInCurve: Curves.easeOutCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: child,
        ),
        child: _hovering ? _panel(palette) : _dashes(palette),
      ),
    );
  }

  Widget _dashes(TracePalette palette) {
    return Column(
      key: const ValueKey('dashes'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final h in widget.headings.take(12))
          Container(
            width: (18.0 - (h.$1 - 1) * 4).clamp(6.0, 18.0),
            height: 2,
            margin: const EdgeInsets.symmetric(vertical: 3),
            decoration: BoxDecoration(
              color: palette.muted.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
      ],
    );
  }

  Widget _panel(TracePalette palette) {
    return Material(
      key: const ValueKey('panel'),
      color: palette.toolbarBg,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 250,
        constraints: const BoxConstraints(maxHeight: 380),
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final h in widget.headings)
                InkWell(
                  onTap: () {
                    setState(() => _hovering = false);
                    widget.onJump(h.$3);
                  },
                  child: Padding(
                    padding: EdgeInsets.only(
                        left: 14.0 + (h.$1 - 1) * 12,
                        right: 14,
                        top: 5,
                        bottom: 5),
                    child: Text(
                      h.$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: palette.fg,
                        fontWeight:
                            h.$1 == 1 ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
