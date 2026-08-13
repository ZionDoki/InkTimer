import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptimer/ui/home/breath_orb.dart';

Widget _orb(double progress) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox.square(
        dimension: 340,
        child: BreathOrb(
          key: const ValueKey('test-orb'),
          progress: progress,
          resting: false,
          paused: false,
          pressed: false,
          time: '00:20',
          phase: '动 作',
          round: '第一组',
        ),
      ),
    ),
  ),
);

Widget _orbWithPause(bool paused) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox.square(
        dimension: 340,
        child: BreathOrb(
          key: const ValueKey('test-orb'),
          progress: 0.5,
          resting: false,
          paused: paused,
          pressed: false,
          time: '00:20',
          phase: '动 作',
          round: '第一组',
        ),
      ),
    ),
  ),
);

Widget _orbHolding(bool holding, {double progress = 0.5}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox.square(
        dimension: 340,
        child: BreathOrb(
          key: const ValueKey('test-orb'),
          progress: progress,
          resting: false,
          paused: false,
          pressed: holding,
          holding: holding,
          time: '00:20',
          phase: '动 作',
          round: '第一组',
        ),
      ),
    ),
  ),
);

double _paintedProgress(WidgetTester tester) {
  final paints = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
  final fluid = paints.singleWhere(
    (paint) => paint.painter.runtimeType.toString() == '_FluidPainter',
  );
  return (fluid.painter as dynamic).progress as double;
}

String _captureShellPath(WidgetTester tester) {
  final notifier = _shellMorphNotifier(tester);
  final path = notifier.getPath(const Size(340, 340));
  // 用路径的边界矩形 + 几何特征作为指纹
  final bounds = path.getBounds();
  return '${bounds.left.toStringAsFixed(3)},${bounds.top.toStringAsFixed(3)},'
      '${bounds.right.toStringAsFixed(3)},${bounds.bottom.toStringAsFixed(3)}';
}

dynamic _shellMorphNotifier(WidgetTester tester) {
  final paints = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
  final shell = paints.firstWhere(
    (paint) => paint.painter.runtimeType.toString() == '_OrbShellPainter',
  );
  return (shell.painter as dynamic).morphNotifier;
}

Rect _shellBounds(WidgetTester tester) =>
    (_shellMorphNotifier(tester).getPath(const Size(340, 340)) as Path)
        .getBounds();

void main() {
  testWidgets('动态液面拥有独立重绘边界，不连带重绘文字与球壳', (tester) async {
    await tester.pumpWidget(_orb(0.25));

    final fluidBoundary = find.byKey(
      const ValueKey('orb-fluid-repaint-boundary'),
    );
    expect(fluidBoundary, findsOneWidget);
    expect(
      find.descendant(
        of: fluidBoundary,
        matching: find.byKey(const ValueKey('timer-time')),
      ),
      findsNothing,
    );
  });

  testWidgets('液面高度在控制器采样点之间按显示帧连续插值', (tester) async {
    await tester.pumpWidget(_orb(0.10));
    await tester.pump(const Duration(milliseconds: 180));
    expect(_paintedProgress(tester), closeTo(0.10, 0.001));

    await tester.pumpWidget(_orb(0.50));
    await tester.pump(const Duration(milliseconds: 40));

    final intermediate = _paintedProgress(tester);
    expect(intermediate, greaterThan(0.10));
    expect(intermediate, lessThan(0.50));

    await tester.pump(const Duration(milliseconds: 180));
    expect(_paintedProgress(tester), closeTo(0.50, 0.001));
  });

  testWidgets('轮廓 morph 动画在运行中持续变化，暂停时冻结', (tester) async {
    await tester.pumpWidget(_orbWithPause(false));
    await tester.pump(const Duration(milliseconds: 100));
    final path1 = _captureShellPath(tester);

    await tester.pump(const Duration(milliseconds: 500));
    final path2 = _captureShellPath(tester);
    expect(path2, isNot(equals(path1)), reason: 'morph 应持续变化');

    // 暂停
    await tester.pumpWidget(_orbWithPause(true));
    await tester.pump(const Duration(milliseconds: 100));
    final pathPaused1 = _captureShellPath(tester);

    await tester.pump(const Duration(milliseconds: 500));
    final pathPaused2 = _captureShellPath(tester);
    expect(pathPaused2, equals(pathPaused1), reason: '暂停时 morph 应冻结');

    // 恢复
    await tester.pumpWidget(_orbWithPause(false));
    await tester.pump(const Duration(milliseconds: 500));
    final pathResumed = _captureShellPath(tester);
    expect(pathResumed, isNot(equals(pathPaused2)), reason: '恢复后 morph 应继续');
  });

  // 回归：首版用非整数角频/时间倍率，导致闭合处硬坎与绕回时突变。
  testWidgets('轮廓形变跏一个完整周期不出现帧间突变', (tester) async {
    await tester.pumpWidget(_orbWithPause(false));
    await tester.pump(const Duration(milliseconds: 16));

    var previous = _shellBounds(tester);
    var worstJump = 0.0;
    // morph 周期 11s，跏 12s 确保跨过一次 controller 绕回
    for (var step = 0; step < 150; step++) {
      await tester.pump(const Duration(milliseconds: 80));
      final current = _shellBounds(tester);
      final jump = math.max(
        (current.width - previous.width).abs(),
        (current.height - previous.height).abs(),
      );
      worstJump = math.max(worstJump, jump);
      previous = current;
    }

    // 80ms 一帧、周期 11s、幅度±1.2%，正常帧间变化远小于 1px。
    // 首版的绕回突变会直接做到 5% 半径（~8px）。
    expect(
      worstJump,
      lessThan(2.0),
      reason:
          '帧间跳变 ${worstJump.toStringAsFixed(3)}px —— '
          '角频率与时间倍率必须取整数才能无缝循环',
    );
  });

  testWidgets('轮廓形变幅度保持克制，不偏离手调形体', (tester) async {
    await tester.pumpWidget(_orbWithPause(false));
    await tester.pump(const Duration(milliseconds: 16));

    var minSize = double.infinity;
    var maxSize = 0.0;
    for (var step = 0; step < 150; step++) {
      await tester.pump(const Duration(milliseconds: 80));
      final b = _shellBounds(tester);
      minSize = math.min(minSize, math.min(b.width, b.height));
      maxSize = math.max(maxSize, math.max(b.width, b.height));
    }

    // 径向调制 ±1.2%；留余量取 6%。首版峰峰值 9.7% 会超。
    final spread = (maxSize - minSize) / maxSize;
    expect(
      spread,
      lessThan(0.06),
      reason:
          '轮廓尺寸波动 ${(spread * 100).toStringAsFixed(2)}% 过大，'
          '水墨球要呼吸感而非蠕动感',
    );
  });

  testWidgets('长按蓄力终止时形变一同屏住，松手后恢复', (tester) async {
    await tester.pumpWidget(_orbHolding(false));
    await tester.pump(const Duration(milliseconds: 100));
    final before = _captureShellPath(tester);

    await tester.pump(const Duration(milliseconds: 500));
    expect(
      _captureShellPath(tester),
      isNot(equals(before)),
      reason: '未长按时形变应在跑',
    );

    await tester.pumpWidget(_orbHolding(true));
    await tester.pump(const Duration(milliseconds: 100));
    final held = _captureShellPath(tester);
    await tester.pump(const Duration(milliseconds: 800));
    expect(_captureShellPath(tester), equals(held), reason: '长按蓄力中形变应屏住');

    await tester.pumpWidget(_orbHolding(false));
    await tester.pump(const Duration(milliseconds: 500));
    expect(_captureShellPath(tester), isNot(equals(held)), reason: '松手后形变应恢复');
  });

  testWidgets('长按蓄力不冻结水位 —— 计时未停，水该继续涨', (tester) async {
    await tester.pumpWidget(_orbHolding(true, progress: 0.20));
    await tester.pump(const Duration(milliseconds: 200));
    expect(_paintedProgress(tester), closeTo(0.20, 0.001));

    await tester.pumpWidget(_orbHolding(true, progress: 0.60));
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      _paintedProgress(tester),
      closeTo(0.60, 0.001),
      reason: '蓄力中水位仍应跟着进度走',
    );
  });

  // 回归：旧实现的时间倍率（0.72 / -0.86 / 0.7 / 0.035+）都不是整数，
  // motion.value 从 1.0 绕回 0.0 时每项都硬跳 —— 表现为每 7s 卡一下。
  group('液面动画必须无缝循环（周期末尾不得硬跳）', () {
    test('波形 —— 后浪与主浪在绕回处连续', () {
      const twoPi = math.pi * 2;
      // 与 _FluidPainter.paint 中实际用的两组参数一致
      const cases = [
        (loops: 1, amplitude: 7.2, cycles: 1.35, secondary: 2.4, offset: 1.8),
        (loops: -1, amplitude: 4.8, cycles: 1.8, secondary: 1.7, offset: 0.0),
      ];
      for (final c in cases) {
        var worst = 0.0;
        for (var i = 0; i <= 44; i++) {
          double y(double value) => orbWaveY(
            ratio: i / 44,
            baseY: 0,
            amplitude: c.amplitude,
            cycles: c.cycles,
            loops: c.loops,
            time: value * twoPi,
            secondaryAmplitude: c.secondary,
            phaseOffset: c.offset,
          );
          worst = math.max(worst, (y(0) - y(1)).abs());
        }
        expect(
          worst,
          lessThan(1e-9),
          reason:
              'loops=${c.loops} 在绕回处跳 '
              '${worst.toStringAsFixed(2)}px；时间倍率必须取整数',
        );
      }
    });

    test('水下光环 —— 横纵均在绕回处连续', () {
      const twoPi = math.pi * 2;
      for (var index = 0; index < 4; index++) {
        final a = orbCausticOffset(index, 0);
        final b = orbCausticOffset(index, twoPi);
        expect((a.dx - b.dx).abs(), lessThan(1e-9), reason: '光环 $index 横向');
        expect((a.dy - b.dy).abs(), lessThan(1e-9), reason: '光环 $index 纵向');
      }
    });

    test('悬浮墨粒 —— 不再在绕回处瞬移', () {
      for (var index = 0; index < 9; index++) {
        final a = orbInkOffset(index, 0);
        final b = orbInkOffset(index, 1);
        expect((a.dx - b.dx).abs(), lessThan(1e-9), reason: '墨粒 $index 横向');
        expect(
          (a.dy - b.dy).abs(),
          lessThan(1e-9),
          reason: '墨粒 $index 纵向 —— 旧线性上升写法此处最大跳 94% 水高',
        );
      }
    });

    test('墨粒定位种子散布在 0..1 且不重叠', () {
      final seeds = [for (var i = 0; i < 9; i++) orbInkSeed(i)];
      for (final s in seeds) {
        expect(s, inInclusiveRange(0, 1));
      }
      expect(seeds.toSet().length, seeds.length, reason: '种子应两两不同');
    });
  });
}
