import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/zen_theme.dart';

class PaperBackground extends StatelessWidget {
  const PaperBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    return ColoredBox(
      color: palette.paper,
      child: CustomPaint(painter: _PaperPainter(palette), child: child),
    );
  }
}

class _PaperPainter extends CustomPainter {
  const _PaperPainter(this.palette);

  final ZenPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final fiber = Paint()
      ..strokeWidth = 0.35
      ..color = palette.isInk
          ? const Color(0x04e8e2d4)
          : const Color(0x05594f40);
    for (var index = 0; index < 34; index++) {
      final seed = _hash(index * 7919);
      final y = seed * size.height;
      final x = _hash(index * 3469 + 5) * size.width;
      final length = 35 + _hash(index * 1601 + 9) * 150;
      final bend = (_hash(index * 1543 + 17) - 0.5) * 4;
      final path = Path()..moveTo(x, y);
      path.cubicTo(
        x + length * 0.28,
        y + bend,
        x + length * 0.72,
        y - bend,
        x + length,
        y + bend * 0.25,
      );
      canvas.drawPath(path, fiber);
    }

    final fleck = Paint()
      ..color = palette.isInk
          ? const Color(0x05e8e2d4)
          : const Color(0x06231f19);
    final columns = math.max(1, (size.width / 22).ceil());
    final rows = math.max(1, (size.height / 22).ceil());
    for (var row = 0; row < rows; row++) {
      for (var column = 0; column < columns; column++) {
        final seed = row * 1013 + column * 1999;
        if (_hash(seed) < 0.44) continue;
        final x = (column + _hash(seed + 1)) * 22;
        final y = (row + _hash(seed + 2)) * 22;
        canvas.drawCircle(Offset(x, y), 0.25 + _hash(seed + 3) * 0.45, fleck);
      }
    }

    final vignette = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.16),
        radius: 0.94,
        colors: [
          Colors.transparent,
          palette.isInk ? const Color(0x52000000) : const Color(0x1a3c3223),
        ],
        stops: const [0.58, 1],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, vignette);
  }

  double _hash(int value) {
    final x = math.sin(value * 12.9898 + 78.233) * 43758.5453;
    return x - x.floorToDouble();
  }

  @override
  bool shouldRepaint(covariant _PaperPainter oldDelegate) =>
      oldDelegate.palette != palette;
}
