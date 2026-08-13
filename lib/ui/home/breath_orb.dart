import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/zen_theme.dart';

class BreathOrb extends StatefulWidget {
  const BreathOrb({
    super.key,
    required this.progress,
    required this.resting,
    required this.paused,
    required this.pressed,
    required this.time,
    required this.phase,
    required this.round,
    this.holding = false,
    this.growthLevel,
  });

  final double progress;
  final bool resting;
  final bool paused;
  final bool pressed;
  final String time;
  final String phase;
  final String round;

  /// 长按蓄力终止中 —— 呼吸与形变屏住，但水位继续（计时未停）。
  final bool holding;

  /// 隐修等级（1-99），用于加深球体色调。null 时使用原始调色板。
  final int? growthLevel;

  @override
  State<BreathOrb> createState() => _BreathOrbState();
}

class _BreathOrbState extends State<BreathOrb> with TickerProviderStateMixin {
  late final AnimationController _motion;
  late final AnimationController _morph;
  late final _OrbMorphNotifier _morphNotifier;

  /// 暂停与长按蓄力都让球屏住呼吸。
  static bool _isFrozen(BreathOrb w) => w.paused || w.holding;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 7000),
    );
    // morph 独立控制器，不可公度周期，随机初相
    final seed = math.Random().nextDouble();
    _morph = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 11000),
      value: seed,
    );
    _morphNotifier = _OrbMorphNotifier(_morph);
    if (!_isFrozen(widget)) {
      _motion.repeat();
      _morph.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant BreathOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasFrozen = _isFrozen(oldWidget);
    final nowFrozen = _isFrozen(widget);
    if (nowFrozen == wasFrozen) return;
    if (nowFrozen) {
      _motion.stop(canceled: false);
      _morph.stop(canceled: false);
    } else {
      _motion.repeat();
      _morph.repeat();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    _morph.dispose();
    _morphNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final basePalette = ZenPalette.of(context);
    final palette = widget.growthLevel != null
        ? basePalette.deepenedForLevel(widget.growthLevel!)
        : basePalette;
    final orb = RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              painter: _OrbShellPainter(
                palette: palette,
                morphNotifier: _morphNotifier,
              ),
            ),
          ),
          _FluidLayer(
            progress: widget.progress.clamp(0, 1),
            resting: widget.resting,
            paused: widget.paused,
            palette: palette,
            motion: _motion,
            morphNotifier: _morphNotifier,
          ),
          RepaintBoundary(
            child: Center(
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.35,
                child: AnimatedOpacity(
                  opacity: widget.paused ? 0.42 : 1,
                  duration: const Duration(milliseconds: 500),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.time,
                        key: const ValueKey('timer-time'),
                        style: TextStyle(
                          fontFamily: 'Cormorant',
                          fontSize: 70,
                          height: 0.92,
                          fontWeight: FontWeight.w300,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: palette.ink,
                          letterSpacing: 0.5,
                        ).variableWeight,
                      ),
                      const SizedBox(height: 16),
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 700),
                        style: TextStyle(
                          fontFamily: 'NotoSerifSC',
                          fontSize: 13,
                          color: widget.resting ? palette.rest : palette.work,
                          letterSpacing: 8,
                        ).variableWeight,
                        child: Text(widget.phase),
                      ),
                      if (widget.round.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          widget.round,
                          style: TextStyle(
                            fontFamily: 'Cormorant',
                            fontSize: 12,
                            color: palette.inkSoft,
                            letterSpacing: 3.4,
                          ).variableWeight,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return AnimatedScale(
      duration: widget.pressed
          ? const Duration(milliseconds: 120)
          : const Duration(milliseconds: 520),
      curve: widget.pressed ? Curves.easeOut : Curves.elasticOut,
      scale: widget.pressed ? 0.955 : 1,
      child: AnimatedBuilder(
        animation: _motion,
        child: orb,
        builder: (context, child) {
          // 画面只做 GPU 缩放；液面由 CustomPainter 的 repaint 直接更新，
          // 不再每帧重建文字、阴影与布局。
          final breathe =
              1 + 0.032 * math.sin(_motion.value * math.pi * 2 - math.pi / 2);
          return Transform.scale(scale: breathe, child: child);
        },
      ),
    );
  }
}

class _FluidLayer extends StatefulWidget {
  const _FluidLayer({
    required this.progress,
    required this.resting,
    required this.paused,
    required this.palette,
    required this.motion,
    required this.morphNotifier,
  });

  final double progress;
  final bool resting;
  final bool paused;
  final ZenPalette palette;
  final Animation<double> motion;
  final _OrbMorphNotifier morphNotifier;

  @override
  State<_FluidLayer> createState() => _FluidLayerState();
}

class _FluidLayerState extends State<_FluidLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _levelController;
  late Animation<double> _level;

  @override
  void initState() {
    super.initState();
    _levelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 130),
    );
    _level = AlwaysStoppedAnimation(widget.progress);
  }

  @override
  void didUpdateWidget(covariant _FluidLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = widget.progress.clamp(0.0, 1.0);
    final current = _level.value;
    final phaseReset = target < current - 0.20;
    if (widget.paused || phaseReset) {
      _levelController.stop();
      _level = AlwaysStoppedAnimation(target);
      return;
    }
    if ((target - current).abs() < 0.00001) return;
    _level = Tween<double>(
      begin: current,
      end: target,
    ).animate(CurvedAnimation(parent: _levelController, curve: Curves.linear));
    _levelController.forward(from: 0);
  }

  @override
  void dispose() {
    _levelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    key: const ValueKey('orb-fluid-repaint-boundary'),
    child: CustomPaint(
      painter: _FluidPainter(
        palette: widget.palette,
        level: _level,
        resting: widget.resting,
        motion: widget.motion,
        morphNotifier: widget.morphNotifier,
      ),
    ),
  );
}

class _OrbShellPainter extends CustomPainter {
  const _OrbShellPainter({required this.palette, required this.morphNotifier})
    : super(repaint: morphNotifier);

  final ZenPalette palette;
  final _OrbMorphNotifier morphNotifier;

  @override
  void paint(Canvas canvas, Size size) {
    final path = morphNotifier.getPath(size);
    final staticShadowPath = _staticOrbPath(size);
    final rect = Offset.zero & size;

    // 投影用静态路径（模糊 18px + 下移 5.5%，形变看不出来）
    canvas.drawPath(
      staticShadowPath.shift(Offset(0, size.height * 0.055)),
      Paint()
        ..color = palette.ink.withValues(alpha: palette.isInk ? 0.20 : 0.14)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.34, -0.42),
          radius: 1.08,
          colors: [
            palette.isInk
                ? palette.paperDeep.withValues(alpha: 0.78)
                : const Color(0xfffcf9f0),
            palette.paperDeep,
            palette.paper,
          ],
          stops: const [0, 0.58, 1],
        ).createShader(rect),
    );

    canvas.save();
    canvas.clipPath(path);
    final fiber = Paint()
      ..strokeWidth = 0.55
      ..color = palette.ink.withValues(alpha: 0.022);
    for (var index = 0; index < 13; index++) {
      final y = size.height * (0.12 + index * 0.064);
      final sway = math.sin(index * 1.73) * size.width * 0.025;
      canvas.drawLine(
        Offset(size.width * 0.18 + sway, y),
        Offset(size.width * 0.82 - sway, y + math.sin(index) * 1.8),
        fiber,
      );
    }
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.40, size.height * 0.24),
        width: size.width * 0.36,
        height: size.height * 0.12,
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: palette.isInk ? 0.025 : 0.22),
    );
    canvas.restore();

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = palette.ink.withValues(alpha: 0.09),
    );
  }

  // morphNotifier 已经 super(repaint:) 注册，形变自动触发重绘
  @override
  bool shouldRepaint(covariant _OrbShellPainter oldDelegate) =>
      oldDelegate.palette != palette;
}

class _FluidPainter extends CustomPainter {
  _FluidPainter({
    required this.palette,
    required this.level,
    required this.resting,
    required this.motion,
    required this.morphNotifier,
  }) : super(repaint: Listenable.merge([motion, level, morphNotifier]));

  final ZenPalette palette;
  final Animation<double> level;
  final bool resting;
  final Animation<double> motion;
  final _OrbMorphNotifier morphNotifier;

  double get progress => level.value;

  @override
  void paint(Canvas canvas, Size size) {
    final progress = this.progress;
    if (progress <= 0.0001) return;
    final orbPath = morphNotifier.getPath(size);
    final rect = Offset.zero & size;
    final phase = resting ? palette.rest : palette.work;
    final phaseSoft = resting ? palette.restSoft : palette.workSoft;
    final phaseGlow = resting ? palette.restGlow : palette.workGlow;
    final time = motion.value * math.pi * 2;
    final fillY = size.height * (1 - progress);

    // 时间相位必须是 loop 的整数倍（见 _wavePath 注释）：
    // 后浪 +1 周/loop，主浪 -1 周/loop，反向对流。
    final rearWave = _wavePath(
      size,
      baseY: fillY + 5,
      amplitude: 7.2,
      cycles: 1.35,
      loops: 1,
      time: time,
      phaseOffset: 1.8,
      secondaryAmplitude: 2.4,
      close: true,
    );
    final bodyWave = _wavePath(
      size,
      baseY: fillY,
      amplitude: 4.8,
      cycles: 1.8,
      loops: -1,
      time: time,
      secondaryAmplitude: 1.7,
      close: true,
    );
    final surface = _wavePath(
      size,
      baseY: fillY,
      amplitude: 4.8,
      cycles: 1.8,
      loops: -1,
      time: time,
      secondaryAmplitude: 1.7,
    );

    canvas.save();
    canvas.clipPath(orbPath);
    canvas.drawPath(
      rearWave,
      Paint()..color = phaseSoft.withValues(alpha: 0.34),
    );
    canvas.drawPath(
      bodyWave,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            phaseSoft.withValues(alpha: 0.72),
            phase.withValues(alpha: palette.isInk ? 0.62 : 0.70),
            phase.withValues(alpha: palette.isInk ? 0.76 : 0.82),
          ],
          stops: const [0, 0.28, 1],
        ).createShader(rect),
    );

    canvas.save();
    canvas.clipPath(bodyWave);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.34, -0.52),
          radius: 0.82,
          colors: [phaseGlow.withValues(alpha: 0.72), Colors.transparent],
        ).createShader(rect),
    );
    _paintCaustics(canvas, size, fillY, time, phaseSoft);
    _paintSuspendedInk(canvas, size, fillY, motion.value, phaseSoft);
    canvas.restore();

    canvas.drawPath(
      surface,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.1
        ..strokeCap = StrokeCap.round
        ..color = phaseSoft.withValues(alpha: 0.92),
    );
    canvas.drawPath(
      surface.shift(const Offset(0, 2.2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.75
        ..color = palette.paper.withValues(alpha: 0.34),
    );
    canvas.restore();
  }

  void _paintCaustics(
    Canvas canvas,
    Size size,
    double fillY,
    double time,
    Color color,
  ) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..color = color.withValues(alpha: 0.22);
    for (var index = 0; index < 4; index++) {
      final offset = orbCausticOffset(index, time);
      final x = size.width * (0.27 + index * 0.16) + offset.dx;
      final y = fillY + size.height * (0.14 + index * 0.11) + offset.dy;
      if (y > size.height * 0.92) continue;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(x, y),
          width: size.width * (0.13 + index * 0.018),
          height: size.height * 0.036,
        ),
        paint,
      );
    }
  }

  void _paintSuspendedInk(
    Canvas canvas,
    Size size,
    double fillY,
    double t,
    Color color,
  ) {
    final waterHeight = size.height - fillY;
    if (waterHeight < 18) return;
    final span = math.max(8, waterHeight - 14);
    for (var index = 0; index < 9; index++) {
      final seed = orbInkSeed(index);
      final offset = orbInkOffset(index, t);
      final x = size.width * (0.18 + ((seed * 1.7) % 1) * 0.64) + offset.dx;
      final y = size.height - 8 - span * (0.12 + 0.76 * seed) + offset.dy;
      if (y <= fillY + 5) continue;
      canvas.drawCircle(
        Offset(x, y),
        0.7 + (index % 3) * 0.45,
        Paint()..color = color.withValues(alpha: 0.14 + (index % 2) * 0.05),
      );
    }
  }

  /// 波形。关键约束：时间相位必须是 loop 的整数倍。
  ///
  /// motion.value 从 1.0 绕回 0.0，若 loops 非整数，每 7s 波形会硬跳一下
  /// —— 旧写法 0.72 / -0.86 实测分别跳 15.2px 与 7.1px。
  /// 次级项的相位也必须同步取整（旧写法乘 0.58，同样跳）。
  Path _wavePath(
    Size size, {
    required double baseY,
    required double amplitude,
    required double cycles,
    required int loops,
    required double time,
    required double secondaryAmplitude,
    double phaseOffset = 0,
    bool close = false,
  }) {
    const segments = 44;
    final path = Path();
    for (var index = 0; index <= segments; index++) {
      final ratio = index / segments;
      final x = size.width * ratio;
      final y = orbWaveY(
        ratio: ratio,
        baseY: baseY,
        amplitude: amplitude,
        cycles: cycles,
        loops: loops,
        time: time,
        secondaryAmplitude: secondaryAmplitude,
        phaseOffset: phaseOffset,
      );
      if (index == 0) {
        path.moveTo(-2, y);
      } else {
        path.lineTo(x, y);
      }
    }
    if (close) {
      path
        ..lineTo(size.width + 2, size.height + 2)
        ..lineTo(-2, size.height + 2)
        ..close();
    }
    return path;
  }

  // morphNotifier 已在 Listenable.merge 中，不用在此比较
  @override
  bool shouldRepaint(covariant _FluidPainter oldDelegate) =>
      oldDelegate.palette != palette ||
      oldDelegate.level != level ||
      oldDelegate.resting != resting ||
      oldDelegate.motion != motion;
}

// ========== 液面动画的纯函数部分 ==========
//
// 铁律：所有随时间变化的项，其时间倍率必须是 loop 的整数倍。
// motion.value 从 1.0 硬绕回 0.0，非整数倍率会在每个周期末尾跳一下。
// 旧实现实测：后浪跳 15.2px、主浪 7.1px、光环 7.8px、
// 墨粒最大一跃 94% 水高。这就是“每隔一阵卡一下”的成因。
//
// 提为顶层纯函数，以便测试直接验证无缝性（见 breath_orb_test.dart）。

/// 波形在横向比例 [ratio] 处的 y。[loops] 为整数周/loop，正负定向。
double orbWaveY({
  required double ratio,
  required double baseY,
  required double amplitude,
  required double cycles,
  required int loops,
  required double time,
  required double secondaryAmplitude,
  double phaseOffset = 0,
}) {
  final phase = time * loops + phaseOffset;
  // 次级项反向漂移，倍率同样取整数
  final secondaryPhase = -time * loops + phaseOffset;
  return baseY +
      math.sin(ratio * math.pi * 2 * cycles + phase) * amplitude +
      math.sin(ratio * math.pi * 2 * 0.72 + secondaryPhase) *
          secondaryAmplitude;
}

/// 第 [index] 道水下光环的漂移量。横纵均 1 周/loop。
Offset orbCausticOffset(int index, double time) =>
    Offset(math.sin(time + index) * 9, math.cos(time + index * 1.4) * 5);

/// 第 [index] 粒墨的定位种子（黄金比散布，不随时间变）。
double orbInkSeed(int index) => (index * 0.61803398875) % 1;

/// 第 [index] 粒墨的漂移量。[t] 是归一相位 0..1。
///
/// 旧写法是线性上升 `(seed + t * rate) % 1`，rate 非整数 —— 绕回时
/// 最大一跃 94% 水高，看上去就是尘埃瞬移。改成整数周的正弦浮沈：
/// 无缝循环，而且“悬浮”本来就比“传送带”更像墨粒。
Offset orbInkOffset(int index, double t) {
  final bobs = 1 + (index % 3); // 1/2/3 周每 loop，深浅错开
  return Offset(
    math.sin(t * math.pi * 2 + index) * 2.5,
    math.sin(t * math.pi * 2 * bobs + index * 1.7) * 6,
  );
}

// ========== 轮廓微形变：保留手调 Bézier 形体，只对控制点做径向调制 ==========
//
// 设计铁律（前一版违反了前两条，导致边缘出缝与突变）：
//  1. 角频率必须是整数 —— 否则 noise(0) != noise(2π)，闭合处一个硬坎。
//  2. 时间倍率必须是整数 —— controller.value 从 1.0 绕回 0.0，
//     非整数会在每轮末尾跳一下。
//  3. 幅度宁小。水墨球要的是“在呼吸”，不是“在蠕动”。
//  4. 不重建形体，只调制原有控制点 —— 手调的不对称才是形体的气质所在。

/// 原手调形体的 13 个定义点，以 (rx, ry) 倍数表示，顺序同 Path 构造。
/// 首尾同为顶点，保证闭合。
const List<(double, double)> _orbAnchorFactors = [
  (0, -1.018), // 顶
  (0.61, -1.04), (1.035, -0.55), (0.984, 0), // → 右
  (1.02, 0.59), (0.54, 1.025), (0, 0.992), // → 底
  (-0.61, 1.035), (-1.025, 0.50), (-1.008, 0), // → 左
  (-1.015, -0.57), (-0.56, -1.018), (0, -1.018), // → 回顶
];

class _OrbMorphNotifier extends ChangeNotifier {
  _OrbMorphNotifier(this._controller) {
    _controller.addListener(notifyListeners);
  }

  final AnimationController _controller;
  Path? _cachedPath;
  Size? _cachedSize;
  double? _cachedPhase;

  Path getPath(Size size) {
    final phase = _controller.value;
    if (_cachedPath != null &&
        _cachedSize == size &&
        (_cachedPhase! - phase).abs() < 0.0001) {
      return _cachedPath!;
    }
    _cachedPath = _buildOrganicPath(size, phase);
    _cachedSize = size;
    _cachedPhase = phase;
    return _cachedPath!;
  }

  Path _buildOrganicPath(Size size, double phase) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final rx = size.width * 0.48;
    final ry = size.height * 0.48;
    final time = phase * math.pi * 2;

    // 两个低频叶片（整数角频 2 与 3），时间倍率也取整数：
    // 空间上严格 2π-周期（无缝），时间上严格 1-周期（绕回无跳）。
    // 2 与 3 叶片以不同速率漂移，叠加出不重样的胖瑕变化。
    // 幅度上限 0.75% + 0.45% = 1.2%（前一版是 9.7%，约 8 倍，因此丑）。
    double radialMod(double angle) =>
        math.sin(angle * 2 + time) * 0.0075 +
        math.sin(angle * 3 - time * 2) * 0.0045;

    // 对每个控制点做径向缩放，保持原拓扑与 rx/ry 纵横比
    final pts = <Offset>[];
    for (final (fx, fy) in _orbAnchorFactors) {
      final angle = math.atan2(fy, fx);
      final k = 1 + radialMod(angle);
      pts.add(Offset(cx + rx * fx * k, cy + ry * fy * k));
    }

    // 四段 cubic，与原形体完全同构 —— 天然平滑，不需插值成百上千条直线
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (var i = 1; i + 2 < pts.length; i += 3) {
      path.cubicTo(
        pts[i].dx,
        pts[i].dy,
        pts[i + 1].dx,
        pts[i + 1].dy,
        pts[i + 2].dx,
        pts[i + 2].dy,
      );
    }
    return path..close();
  }

  @override
  void dispose() {
    _controller.removeListener(notifyListeners);
    super.dispose();
  }
}

// 静态路径：仅用于投影（原 _organicOrbPath）
Path _staticOrbPath(Size size) {
  final cx = size.width / 2;
  final cy = size.height / 2;
  final rx = size.width * 0.48;
  final ry = size.height * 0.48;
  return Path()
    ..moveTo(cx, cy - ry * 1.018)
    ..cubicTo(
      cx + rx * 0.61,
      cy - ry * 1.04,
      cx + rx * 1.035,
      cy - ry * 0.55,
      cx + rx * 0.984,
      cy,
    )
    ..cubicTo(
      cx + rx * 1.02,
      cy + ry * 0.59,
      cx + rx * 0.54,
      cy + ry * 1.025,
      cx,
      cy + ry * 0.992,
    )
    ..cubicTo(
      cx - rx * 0.61,
      cy + ry * 1.035,
      cx - rx * 1.025,
      cy + ry * 0.50,
      cx - rx * 1.008,
      cy,
    )
    ..cubicTo(
      cx - rx * 1.015,
      cy - ry * 0.57,
      cx - rx * 0.56,
      cy - ry * 1.018,
      cx,
      cy - ry * 1.018,
    )
    ..close();
}
