import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

/// An ambient, non-intrusive circular progress ring displaying
/// daily writing goal progress.
class ProgressRing extends StatelessWidget {
  final int currentWords;
  final int goalWords;
  final TracePalette palette;
  final double size;
  final double strokeWidth;

  const ProgressRing({
    super.key,
    required this.currentWords,
    required this.goalWords,
    required this.palette,
    this.size = 28.0,
    this.strokeWidth = 2.5,
  });

  @override
  Widget build(BuildContext context) {
    if (goalWords <= 0) return const SizedBox.shrink();

    final progress = (currentWords / goalWords).clamp(0.0, 1.0);
    final percent = (progress * 100).toInt();

    return Tooltip(
      message: 'Daily Goal: $currentWords / $goalWords words ($percent%)',
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _ProgressRingPainter(
            progress: progress,
            accentColor: palette.accent,
            trackColor: palette.border,
            strokeWidth: strokeWidth,
            isComplete: currentWords >= goalWords,
          ),
        ),
      ),
    );
  }
}

class _ProgressRingPainter extends CustomPainter {
  final double progress;
  final Color accentColor;
  final Color trackColor;
  final double strokeWidth;
  final bool isComplete;

  _ProgressRingPainter({
    required this.progress,
    required this.accentColor,
    required this.trackColor,
    required this.strokeWidth,
    required this.isComplete,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Track
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    // Progress Arc
    if (progress > 0.0) {
      final progressPaint = Paint()
        ..color = isComplete ? const Color(0xFF1A7F37) : accentColor
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = strokeWidth;

      const startAngle = -math.pi / 2;
      final sweepAngle = 2 * math.pi * progress;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_ProgressRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.accentColor != accentColor ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.isComplete != isComplete;
}
