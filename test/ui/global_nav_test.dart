import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptimer/ui/theme/zen_theme.dart';
import 'package:uptimer/ui/widgets/global_nav.dart';

class _NavHarness extends StatefulWidget {
  const _NavHarness({this.disableAnimations = false});

  final bool disableAnimations;

  @override
  State<_NavHarness> createState() => _NavHarnessState();
}

class _NavHarnessState extends State<_NavHarness> {
  GlobalNavDestination current = GlobalNavDestination.focus;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: buildZenTheme(ink: false),
    home: MediaQuery(
      data: const MediaQueryData(
        size: Size(400, 800),
        devicePixelRatio: 2.0,
      ).copyWith(disableAnimations: widget.disableAnimations),
      child: Scaffold(
        body: GlobalNav(
          current: current,
          onFocus: () => setState(() => current = GlobalNavDestination.focus),
          onGoals: () => setState(() => current = GlobalNavDestination.goals),
        ),
      ),
    ),
  );
}

final _slider = find.byKey(const ValueKey('global-nav-slider'));

void main() {
  testWidgets('专注目标之间无分隔线并共用一个悬浮滑块', (tester) async {
    await tester.pumpWidget(const _NavHarness());

    expect(_slider, findsOneWidget);
    final tabs = tester.widget<Row>(
      find.byKey(const ValueKey('global-nav-tabs')),
    );
    expect(tabs.children, hasLength(2));
    expect(tabs.children.every((child) => child is Expanded), isTrue);
  });

  // 「丝滑」的可测定义：位移单向逼近、不越位、不空转；
  // 生命感交给等体积形变，而不是靠位置抖动。
  testWidgets('滑块位移单向逼近目标，全程不越位', (tester) async {
    await tester.pumpWidget(const _NavHarness());
    final startX = tester.getCenter(_slider).dx;

    await tester.tap(find.byKey(const ValueKey('global-nav-goals')));
    await tester.pump();
    expect(tester.getCenter(_slider).dx, closeTo(startX, 0.01));

    final samples = <double>[];
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      samples.add(tester.getCenter(_slider).dx);
    }
    await tester.pumpAndSettle();
    final settledX = tester.getCenter(_slider).dx;

    expect(settledX, greaterThan(startX + 80), reason: '应真的滑到右侧入口');

    for (var i = 1; i < samples.length; i++) {
      expect(
        samples[i],
        greaterThanOrEqualTo(samples[i - 1] - 0.01),
        reason: '第 $i 帧回退了，位移必须单向',
      );
    }
    for (var i = 0; i < samples.length; i++) {
      expect(
        samples[i],
        lessThanOrEqualTo(settledX + 0.01),
        reason: '第 $i 帧越过了目标位；越位读作松散，不是丝滑',
      );
    }
  });

  testWidgets('滑行途中横向拉伸、停稳后回正（等体积形变）', (tester) async {
    await tester.pumpWidget(const _NavHarness());
    await tester.tap(find.byKey(const ValueKey('global-nav-goals')));
    await tester.pump();

    var peakStretch = 0.0;
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 20));
      // 形变体现在 Transform.scale 上，它是 slider 的直接子节点
      final slider = tester.widget<Transform>(
        find.descendant(of: _slider, matching: find.byType(Transform)),
      );
      final mx = slider.transform.getMaxScaleOnAxis();
      peakStretch = math.max(peakStretch, mx);
    }
    expect(peakStretch, greaterThan(1.02), reason: '滑行中应能看出横向拉伸');

    await tester.pumpAndSettle();
    final settled = tester.widget<Transform>(
      find.descendant(of: _slider, matching: find.byType(Transform)),
    );
    expect(
      settled.transform.getMaxScaleOnAxis(),
      closeTo(1.0, 0.005),
      reason: '停稳后必须回正，不能留着变形',
    );
  });

  testWidgets('系统开启减弱动效时滑块直接就位', (tester) async {
    await tester.pumpWidget(const _NavHarness(disableAnimations: true));
    final startX = tester.getCenter(_slider).dx;

    await tester.tap(find.byKey(const ValueKey('global-nav-goals')));
    await tester.pump();

    expect(
      tester.getCenter(_slider).dx,
      greaterThan(startX + 80),
      reason: '减弱动效时不应还有滑行过程',
    );
  });

  group('位移曲线的数值约束（丝滑的成因，别改回去）', () {
    double velocityAt(Curve c, double t) {
      const h = 0.004;
      final a = c.transform((t - h).clamp(0.0, 1.0));
      final b = c.transform((t + h).clamp(0.0, 1.0));
      return (b - a) / (2 * h);
    }

    test('峰值速度不超过平均速度的 3.5 倍（不窜动）', () {
      var peak = 0.0;
      for (var i = 0; i <= 2000; i++) {
        peak = math.max(peak, velocityAt(navMotionCurve, i / 2000).abs());
      }
      // 旧曲线 easeInOutCubicEmphasized 实测 10.48 —— 先猛窜再停滞
      expect(peak, lessThan(3.5), reason: '峰值速度 $peak 过高，会看到窜动');
    });

    test('尾部空转不超过 30% 时长（不拖沓）', () {
      var t95 = 1.0;
      for (var i = 0; i <= 2000; i++) {
        final t = i / 2000;
        if (navMotionCurve.transform(t) >= 0.95) {
          t95 = t;
          break;
        }
      }
      // 旧曲线实测 50.2% 的时长在爬最后 5%，看起来就是「卡住了」
      final deadTail = 1 - t95;
      expect(
        deadTail,
        lessThan(0.30),
        reason: '${(deadTail * 100).toStringAsFixed(1)}% 的时长在爬最后 5%，会显得停滞',
      );
    });

    test('曲线零越位', () {
      for (var i = 0; i <= 2000; i++) {
        expect(navMotionCurve.transform(i / 2000), lessThanOrEqualTo(1.0));
      }
    });

    test('形变在首末两端归零，中途才起（无突变）', () {
      expect(navStretchAt(0), lessThan(0.02), reason: '起手不能突然变形');
      expect(navStretchAt(1), lessThan(0.02), reason: '停稳必须完全回正');
      var peak = 0.0;
      for (var i = 0; i <= 1000; i++) {
        peak = math.max(peak, navStretchAt(i / 1000));
      }
      expect(peak, closeTo(1.0, 0.02), reason: '中途应达到满幅形变');
    });

    test('形变等体积：横向拉长多少，纵向就压扁多少', () {
      for (final s in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        final squish = navSquish(s);
        expect(
          squish.x * squish.y,
          closeTo(1.0, 1e-9),
          reason: 'stretch=$s 时面积未守恒，形变会显得在膨胀',
        );
      }
      expect(navSquish(0).x, 1.0);
      expect(navSquish(1).x, closeTo(1.06, 1e-9), reason: '满幅拉伸控制在 6%');
    });
  });
}
