import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/zen_theme.dart';

enum GlobalNavDestination { focus, goals }

/// 滑块与路由转场共用的时长。
///
/// 旧值 520ms 配 [Curves.easeInOutCubicEmphasized]：实测该曲线 50.2% 的时长
/// 花在爬最后 5% 的位移上，峰值速度是平均速度的 10.5 倍 —— 先猛地一窜、
/// 再长时间几乎不动，这正是「滑块不丝滑」的来源。
/// 换 [navMotionCurve] 后位移分布均匀，缩到 400ms 反而更快也更顺。
const globalNavSlideDuration = Duration(milliseconds: 400);

/// 滑块位移曲线。选择依据（数值实测，见 navStretchAt 注释）：
/// 首末速度均为 0（形变才能连续起落）、峰值速度仅 2.93 倍（无窜动）、
/// 尾部空转仅 27%（不拖沓）、零越位（越位读作松散，不是丝滑）。
const navMotionCurve = Curves.fastOutSlowIn;

/// [navMotionCurve] 的峰值速度，用于把速度归一到 0..1。
///
/// 实测值：easeInOutCubicEmphasized 10.48 / easeOutBack 5.14 /
/// easeOutQuint 4.96 / fastOutSlowIn 2.93。数值越小越不窜。
const _navCurvePeakVelocity = 2.93;

const _globalNavSliderHeroTag = 'global-nav-slider-hero';

/// 滑块在进度 [t] 处的形变强度 0..1，取自 [navMotionCurve] 的归一化速度。
///
/// 液态玻璃的「液态」来自等体积形变：走得越快、横向拉得越长、纵向压得越扁，
/// 停下时自然回正。它是速度的函数而非额外的位移，所以永远不会和位移打架 ——
/// 旧实现叠了 sway 横摆、lift 纵跳、tilt 旋转三层装饰位移去和主曲线抢，
/// 那是「不顺」的第二个来源。
///
/// 首末速度为 0 保证形变从 0 起、回 0 落，无突变。
double navStretchAt(double t) {
  const h = 0.004;
  final a = navMotionCurve.transform((t - h).clamp(0.0, 1.0));
  final b = navMotionCurve.transform((t + h).clamp(0.0, 1.0));
  final velocity = ((b - a) / (2 * h)).abs();
  return (velocity / _navCurvePeakVelocity).clamp(0.0, 1.0);
}

/// 等体积形变：横向拉长 [stretch]·6%，纵向按倒数压扁，面积守恒。
({double x, double y}) navSquish(double stretch) {
  final sx = 1 + stretch * 0.06;
  return (x: sx, y: 1 / sx);
}

/// 首页与目标页共用的悬浮液态玻璃胶囊导航。
class GlobalNav extends StatelessWidget {
  const GlobalNav({
    super.key,
    required this.current,
    required this.onFocus,
    required this.onGoals,
    this.todoCount = 0,
    this.dim = false,
  });

  final GlobalNavDestination current;
  final VoidCallback onFocus;
  final VoidCallback onGoals;
  final int todoCount;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    final width = math.min(MediaQuery.sizeOf(context).width - 40, 240.0);
    const radius = 28.0;
    return SafeArea(
      key: const ValueKey('global-nav'),
      top: false,
      minimum: const EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: width,
          height: 52,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              boxShadow: [
                BoxShadow(
                  color: palette.ink.withValues(alpha: 0.10),
                  blurRadius: 32,
                  offset: const Offset(0, 14),
                ),
                BoxShadow(
                  color: palette.ink.withValues(alpha: 0.06),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: BackdropFilter(
                // 液态玻璃不只是模糊：折射会把背后的色彩挤压得更浓。
                // 先提饱和再模糊，玻璃才有「厚度」而非一层磨砂。
                filter: ImageFilter.compose(
                  outer: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                  inner: ColorFilter.matrix(_saturate(1.35)),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.paper.withValues(alpha: dim ? 0.52 : 0.68),
                    borderRadius: BorderRadius.circular(radius),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(
                          alpha: palette.isInk ? 0.07 : 0.46,
                        ),
                        palette.paperDeep.withValues(alpha: 0.10),
                        palette.paperDeep.withValues(alpha: 0.34),
                      ],
                      stops: const [0, 0.55, 1],
                    ),
                  ),
                  child: CustomPaint(
                    // 壳体边缘光：顶亮底暗的一圈镜面反射
                    painter: _GlassRimPainter(
                      radius: radius,
                      isInk: palette.isInk,
                      ink: palette.ink,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: Stack(
                        key: const ValueKey('global-nav-stack'),
                        fit: StackFit.expand,
                        children: [
                          _SliderTrack(
                            current: current,
                            accent: current == GlobalNavDestination.focus
                                ? palette.work
                                : palette.rest,
                          ),
                          Row(
                            key: const ValueKey('global-nav-tabs'),
                            children: [
                              Expanded(
                                child: _GlassTab(
                                  key: const ValueKey('global-nav-focus'),
                                  label: '专 注',
                                  semanticsLabel: '专 注 页',
                                  selected:
                                      current == GlobalNavDestination.focus,
                                  accent: palette.work,
                                  dim: dim,
                                  onPressed: onFocus,
                                ),
                              ),
                              Expanded(
                                child: _GlassTab(
                                  key: const ValueKey('global-nav-goals'),
                                  label: '目 标',
                                  semanticsLabel: '目 标 页',
                                  selected:
                                      current == GlobalNavDestination.goals,
                                  accent: palette.rest,
                                  dim: dim,
                                  count: todoCount,
                                  onPressed: onGoals,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 饱和度矩阵。s=1 为原样，>1 提饱和。
List<double> _saturate(double s) {
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  return <double>[
    lr + (1 - lr) * s, lg * (1 - s), lb * (1 - s), 0, 0, //
    lr * (1 - s), lg + (1 - lg) * s, lb * (1 - s), 0, 0, //
    lr * (1 - s), lg * (1 - s), lb + (1 - lb) * s, 0, 0, //
    0, 0, 0, 1, 0,
  ];
}

/// 滑块轨道。自己持有控制器，位移与形变都由同一个动画值派生，
/// 保证两者永远同相 —— 旧实现里 AnimatedAlign(easeOutBack) 与 Hero
/// (easeInOutCubicEmphasized) 是两套独立时钟，互相错拍。
class _SliderTrack extends StatefulWidget {
  const _SliderTrack({required this.current, required this.accent});

  final GlobalNavDestination current;
  final Color accent;

  @override
  State<_SliderTrack> createState() => _SliderTrackState();
}

class _SliderTrackState extends State<_SliderTrack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: globalNavSlideDuration,
    value: widget.current == GlobalNavDestination.focus ? 0 : 1,
  );

  @override
  void didUpdateWidget(_SliderTrack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.current == oldWidget.current) return;
    final target = widget.current == GlobalNavDestination.focus ? 0.0 : 1.0;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = target;
    } else {
      _controller.animateTo(target, curve: Curves.linear);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          // 控制器走线性，曲线在此施加：位移与形变同源同相。
          final raw = _controller.value;
          final eased = navMotionCurve.transform(raw);
          final stretch = navStretchAt(raw);
          return Align(
            alignment: Alignment(eased * 2 - 1, 0),
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Hero(
                  tag: _globalNavSliderHeroTag,
                  transitionOnUserGestures: true,
                  createRectTween: (begin, end) =>
                      _NavSliderRectTween(begin: begin, end: end),
                  flightShuttleBuilder: _sliderFlightShuttle,
                  child: _LiquidGlassSlider(
                    key: const ValueKey('global-nav-slider'),
                    accent: widget.accent,
                    stretch: stretch,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LiquidGlassSlider extends StatelessWidget {
  const _LiquidGlassSlider({
    super.key,
    required this.accent,
    required this.stretch,
  });

  final Color accent;

  /// 0..1 形变强度，来自 [navStretchAt]。
  final double stretch;

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    final isInk = palette.isInk;
    final squish = navSquish(stretch);
    const radius = 27.0;

    return Transform.scale(
      scaleX: squish.x,
      scaleY: squish.y,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: accent.withValues(alpha: 0.16)),
          boxShadow: [
            // accent 底光：玻璃把重心的颜色透到纸面上
            BoxShadow(
              color: accent.withValues(alpha: 0.14 + stretch * 0.05),
              blurRadius: 18,
              spreadRadius: -3,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. 基底 + 折射梯度：上缘透光、下缘积色，玻璃才有厚度
              DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.paper.withValues(alpha: isInk ? 0.13 : 0.62),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: isInk ? 0.10 : 0.62),
                      accent.withValues(alpha: 0.05),
                      palette.paperDeep.withValues(alpha: isInk ? 0.22 : 0.30),
                    ],
                    stops: const [0, 0.5, 1],
                  ),
                ),
              ),
              // 保留半透明折射渐变，但去掉按钮表面的白色镜面高光。
              // 液态感由形变、accent 边缘和底部光晕提供。
            ],
          ),
        ),
      ),
    );
  }
}

/// 壳体外圈边缘光：顶部亮、底部隐，模拟环境光打在玻璃上沿。
class _GlassRimPainter extends CustomPainter {
  const _GlassRimPainter({
    required this.radius,
    required this.isInk,
    required this.ink,
  });

  final double radius;
  final bool isInk;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(0.5),
      Radius.circular(radius - 0.5),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: isInk ? 0.20 : 0.90),
            Colors.white.withValues(alpha: isInk ? 0.05 : 0.28),
            ink.withValues(alpha: 0.10),
          ],
          stops: const [0, 0.45, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _GlassRimPainter old) =>
      old.isInk != isInk || old.ink != ink || old.radius != radius;
}

Widget _sliderFlightShuttle(
  BuildContext flightContext,
  Animation<double> animation,
  HeroFlightDirection direction,
  BuildContext fromHeroContext,
  BuildContext toHeroContext,
) {
  final destinationHero = toHeroContext.widget as Hero;
  final slider = destinationHero.child as _LiquidGlassSlider;
  return AnimatedBuilder(
    animation: animation,
    builder: (context, _) {
      // 与轨道内滑行同一套形变，跨路由飞行时手感不变。
      // 旧实现在此额外叠了 pulse 缩放与 tilt 旋转 —— 圆角胶囊上的
      // 微旋转读作抖动，是「不顺」的第三个来源。
      return _LiquidGlassSlider(
        accent: slider.accent,
        stretch: navStretchAt(animation.value),
      );
    },
  );
}

class _NavSliderRectTween extends RectTween {
  _NavSliderRectTween({required super.begin, required super.end});

  @override
  Rect? lerp(double t) {
    final start = begin;
    final finish = end;
    if (start == null || finish == null) return super.lerp(t);
    // 只有位移，没有 sway/lift 装饰位移。形变交给 shuttle 的 scale 表达。
    return Rect.lerp(start, finish, navMotionCurve.transform(t));
  }
}

class _GlassTab extends StatefulWidget {
  const _GlassTab({
    super.key,
    required this.label,
    required this.semanticsLabel,
    required this.selected,
    required this.accent,
    required this.dim,
    required this.onPressed,
    this.count = 0,
  });

  final String label;
  final String semanticsLabel;
  final bool selected;
  final Color accent;
  final bool dim;
  final VoidCallback onPressed;
  final int count;

  @override
  State<_GlassTab> createState() => _GlassTabState();
}

class _GlassTabState extends State<_GlassTab> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    final textColor = widget.selected
        ? palette.ink
        : palette.inkSoft.withValues(alpha: widget.dim ? 0.62 : 0.88);
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.semanticsLabel,
      child: TextButton(
        onPressed: widget.onPressed,
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          foregroundColor: textColor,
          overlayColor: Colors.transparent,
          splashFactory: NoSplash.splashFactory,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
        ),
        child: Listener(
          onPointerDown: (_) => setState(() => _pressed = true),
          onPointerUp: (_) => setState(() => _pressed = false),
          onPointerCancel: (_) => setState(() => _pressed = false),
          child: AnimatedScale(
            // 按下时轻微下沉，像按在一层软玻璃上
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOutCubic,
            scale: _pressed ? 0.955 : (widget.selected ? 1.02 : 1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: globalNavSlideDuration,
                  curve: navMotionCurve,
                  width: widget.selected ? 5 : 4,
                  height: widget.selected ? 5 : 4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.selected ? widget.accent : palette.inkFaint,
                    boxShadow: widget.selected
                        ? [
                            BoxShadow(
                              color: widget.accent.withValues(alpha: 0.32),
                              blurRadius: 7,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    style: inkText(
                      context,
                      size: 12,
                      color: textColor,
                      spacing: 3.2,
                    ),
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                    ),
                  ),
                ),
                if (widget.count > 0) ...[
                  const SizedBox(width: 7),
                  Container(
                    key: const ValueKey('global-nav-goal-count'),
                    constraints: const BoxConstraints(minWidth: 18),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: widget.accent.withValues(
                        alpha: widget.selected ? 0.18 : 0.11,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      widget.count > 99 ? '99+' : '${widget.count}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.1,
                        color: widget.selected ? palette.ink : palette.inkSoft,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
