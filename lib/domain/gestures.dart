import 'dart:math' as math;

enum DragAxis { x, y }

class DoubleTapGuard {
  DoubleTapGuard({this.windowMs = 350, this.radiusPx = 40});

  final int windowMs;
  final double radiusPx;
  double _lastX = 0;
  double _lastY = 0;
  int? _lastAt;

  bool tap(double x, double y, int now) {
    final lastAt = _lastAt;
    final isDouble =
        lastAt != null &&
        now - lastAt <= windowMs &&
        math.sqrt(math.pow(x - _lastX, 2) + math.pow(y - _lastY, 2)) <=
            radiusPx;
    _lastX = x;
    _lastY = y;
    _lastAt = isDouble ? null : now;
    return isDouble;
  }

  void reset() => _lastAt = null;
}

DragAxis? lockAxis(double dx, double dy, [double threshold = 24]) {
  final absX = dx.abs();
  final absY = dy.abs();
  if (absX < threshold && absY < threshold) return null;
  return absX >= absY ? DragAxis.x : DragAxis.y;
}

double dampen(double distance, [double cap = 56]) =>
    (distance * 0.4).clamp(-cap, cap);

const longPressMs = 2500;

double longPressProgress(int startedAt, int now) =>
    ((now - startedAt) / longPressMs).clamp(0, 1);
