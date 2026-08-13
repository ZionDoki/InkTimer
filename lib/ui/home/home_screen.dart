import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/gestures.dart';
import '../../domain/models.dart';
import '../../domain/schedule.dart';
import '../../domain/sounds.dart';
import '../../domain/stats.dart';
import '../../domain/timer_engine.dart';
import '../../state/app_controller.dart';
import '../settings/settings_page.dart';
import '../stats/stats_page.dart';
import '../templates/template_drawer.dart';
import '../theme/zen_theme.dart';
import '../todos/todos_page.dart';
import '../widgets/global_nav.dart';
import '../widgets/paper_background.dart';
import 'breath_orb.dart';
import 'timer_gesture_surface.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _pressed = false;
  double _holdProgress = 0;
  Timer? _holdTimer;
  bool _holdCuePlayed = false;
  bool _holdCompletedStop = false;
  bool _showGuide = false;
  Timer? _noticeTimer;
  String? _trackedNotice;

  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_controllerChanged);
    _showGuide = controller.ready && !controller.seenGuide;
    _controllerChanged();
  }

  @override
  void dispose() {
    controller.removeListener(_controllerChanged);
    _holdTimer?.cancel();
    _noticeTimer?.cancel();
    super.dispose();
  }

  void _controllerChanged() {
    if (!mounted) return;
    if (controller.notice != null && controller.notice != _trackedNotice) {
      _trackedNotice = controller.notice;
      _noticeTimer?.cancel();
      _noticeTimer = Timer(const Duration(seconds: 4), () {
        controller.clearNotice();
        _trackedNotice = null;
      });
    }
    setState(() {});
  }

  Future<void> _doubleTap() async {
    if (_showGuide || !controller.ready) return;
    switch (controller.timer.status) {
      case TimerStatus.idle:
        await controller.startSelectedSession();
      case TimerStatus.running:
      case TimerStatus.paused:
        await controller.togglePause();
      case TimerStatus.done:
        await controller.resetToIdle();
    }
  }

  void _startHold() {
    if (!controller.hasActiveSession || _holdTimer != null) return;
    _holdCuePlayed = false;
    _holdCompletedStop = false;
    _holdTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      final progress = longPressProgress(0, timer.tick * 16);
      if (!mounted) return;
      setState(() => _holdProgress = progress);
      if (progress >= 1) {
        _holdCompletedStop = true;
        _cancelHold(reset: false);
        unawaited(controller.stopSession());
        if (mounted) setState(() => _holdProgress = 0);
      }
    });
  }

  void _recognizeHold() {
    if (_holdTimer == null || _holdCuePlayed) return;
    _holdCuePlayed = true;
    unawaited(controller.playCue(SoundName.charge));
  }

  void _cancelHold({bool reset = true}) {
    _holdTimer?.cancel();
    _holdTimer = null;
    _holdCuePlayed = false;
    if (reset && mounted) setState(() => _holdProgress = 0);
  }

  void _recognizedHoldReleased() {
    if (_holdCompletedStop) return;
    controller.recordCanceledHold();
  }

  String _timerSemanticsLabel(TimerStatus status) => switch (status) {
    TimerStatus.idle => '开始专注',
    TimerStatus.running => '暂停专注',
    TimerStatus.paused => '继续专注',
    TimerStatus.done => '返回待机',
  };

  Future<void> _openTemplates() async {
    if (controller.hasActiveSession || _showGuide) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: ZenPalette.of(context).ink.withValues(alpha: 0.13),
      constraints: const BoxConstraints(maxWidth: double.infinity),
      builder: (context) => TemplateDrawer(controller: controller),
    );
  }

  Future<void> _openPage(
    Widget page, {
    Duration transitionDuration = const Duration(milliseconds: 220),
    Duration reverseTransitionDuration = const Duration(milliseconds: 180),
  }) async {
    if (_showGuide) return;
    controller.recordInAppDiversion();
    await Navigator.of(context).push<void>(
      PageRouteBuilder(
        pageBuilder: (_, animation, secondaryAnimation) => page,
        transitionsBuilder: (_, animation, secondaryAnimation, child) =>
            FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              ),
              child: child,
            ),
        transitionDuration: transitionDuration,
        reverseTransitionDuration: reverseTransitionDuration,
      ),
    );
  }

  Future<void> _openTodos() async {
    // 往返同时长：滑块 Hero 飞行受路由动画驱动，两头不等长会让
    // 回程手感和去程不一致。
    await _openPage(
      TodosPage(controller: controller),
      transitionDuration: globalNavSlideDuration,
      reverseTransitionDuration: globalNavSlideDuration,
    );
  }

  Future<void> _dismissGuide() async {
    setState(() => _showGuide = false);
    await controller.markGuideSeen();
  }

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    final view = controller.timer;
    final template = controller.displayTemplate;
    final compiled = _safeCompile(template);
    final roundsTotal = compiled.lastOrNull?.roundsTotal ?? 1;
    final effectiveRound = view.status == TimerStatus.idle
        ? 1
        : view.status == TimerStatus.done
        ? roundsTotal
        : view.round;
    final effectiveRoundsTotal =
        view.status == TimerStatus.idle || view.status == TimerStatus.done
        ? roundsTotal
        : view.roundsTotal;
    final resting =
        view.status != TimerStatus.idle &&
        view.phase != null &&
        view.phase!.kind != PhaseKind.work;
    final phaseColor = resting ? palette.rest : palette.work;
    final size = MediaQuery.sizeOf(context);
    final contentCenterY = _focusContentCenterY(size);
    final orbSize = math.min(
      340.0,
      math.min(size.width * 0.74, math.min(size.width, size.height) * 0.68),
    );
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PaperBackground(
        child: SafeArea(
          child: Stack(
            children: [
              if (view.status == TimerStatus.idle)
                Positioned.fill(
                  child: TimerGestureSurface(
                    key: const ValueKey('idle-gesture-surface'),
                    onDoubleTap: () => unawaited(_doubleTap()),
                    onPressedChanged: (pressed) =>
                        setState(() => _pressed = pressed),
                    semanticLabel: _timerSemanticsLabel(view.status),
                    onSemanticTap: () => unawaited(_doubleTap()),
                    child: _IdleTemplateCard(
                      template: template,
                      pressed: _pressed,
                      onOpenTemplates: _openTemplates,
                      growthLevel: controller.growth.level,
                    ),
                  ),
                )
              else
                Positioned.fill(
                  child: TimerGestureSurface(
                    key: const ValueKey('active-gesture-surface'),
                    onDoubleTap: () => unawaited(_doubleTap()),
                    onPressedChanged: (pressed) =>
                        setState(() => _pressed = pressed),
                    onHoldDown: controller.hasActiveSession ? _startHold : null,
                    onHoldRecognized: controller.hasActiveSession
                        ? _recognizeHold
                        : null,
                    onHoldEnd: controller.hasActiveSession ? _cancelHold : null,
                    onRecognizedHoldReleased: controller.hasActiveSession
                        ? _recognizedHoldReleased
                        : null,
                    semanticLabel: _timerSemanticsLabel(view.status),
                    onSemanticTap: () => unawaited(_doubleTap()),
                    onSemanticLongPress: controller.hasActiveSession
                        ? () => unawaited(controller.stopSession())
                        : null,
                    child: const SizedBox.expand(),
                  ),
                ),

              if (view.status != TimerStatus.idle)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 760),
                  curve: Curves.easeInOutCubic,
                  left: 0,
                  right: 0,
                  top:
                      _orbCenterY(size, done: view.status == TimerStatus.done) -
                      math.min(size.width * 0.72, 520) * 0.5,
                  child: IgnorePointer(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 700),
                      child: AnimatedOpacity(
                        key: ValueKey(
                          'phase-mark-${view.status.name}-${resting ? 'rest' : 'work'}',
                        ),
                        duration: const Duration(milliseconds: 500),
                        opacity: view.status == TimerStatus.done ? 0.35 : 1,
                        child: Text(
                          resting ? '靜' : '動',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'NotoSerifSC',
                            fontSize: math.min(size.width * 0.72, 520),
                            fontWeight: FontWeight.w200,
                            height: 1,
                            color: phaseColor.withValues(alpha: 0.05),
                          ).variableWeight,
                        ),
                      ),
                    ),
                  ),
                ),

              if (view.status != TimerStatus.idle)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 760),
                  curve: Curves.easeInOutCubic,
                  left: 0,
                  right: 0,
                  top:
                      _orbCenterY(size, done: view.status == TimerStatus.done) -
                      orbSize * 0.5,
                  child: IgnorePointer(
                    child: Center(
                      child: SizedBox(
                        width: orbSize,
                        height: orbSize,
                        child: BreathOrb(
                          progress: view.status == TimerStatus.done
                              ? 1
                              : view.status == TimerStatus.running ||
                                    view.status == TimerStatus.paused
                              ? view.phaseProgress
                              : 0,
                          resting: resting,
                          paused: view.status == TimerStatus.paused,
                          pressed: _pressed,
                          // 长按蓄力终止中，呼吸与形变随蓄力圈一同屏住
                          holding: _holdProgress > 0,
                          growthLevel: controller.growth.level,
                          time: _timeText(template, compiled, view),
                          phase: _phaseWord(template, compiled, view),
                          round: _roundWord(
                            view,
                            effectiveRound,
                            effectiveRoundsTotal,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              if (view.status != TimerStatus.idle)
                Positioned(
                  top: 24,
                  left: 70,
                  right: 70,
                  child: _TemplateMenuHeader(
                    template: template,
                    enabled: !controller.hasActiveSession,
                    onPressed: _openTemplates,
                  ),
                ),

              if (controller.hasActiveSession)
                Positioned(
                  left: 0,
                  right: 0,
                  top: contentCenterY + orbSize * 0.5 + 22,
                  child: Center(
                    child: IgnorePointer(
                      child: Semantics(
                        button: true,
                        label: '长 按 终 止',
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                          child: Stack(
                            children: [
                              Text(
                                '长 按 终 止',
                                style: inkText(
                                  context,
                                  size: 12,
                                  color: palette.inkSoft,
                                  spacing: 6,
                                ),
                              ),
                              ClipRect(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: _holdProgress,
                                  child: Text(
                                    '长 按 终 止',
                                    style: inkText(
                                      context,
                                      size: 12,
                                      color: palette.work,
                                      spacing: 6,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

              if (view.status != TimerStatus.idle && effectiveRoundsTotal > 1)
                Positioned(
                  left: 80,
                  right: 80,
                  bottom: _roundStonesBottom(size),
                  child: _RoundStones(
                    round: effectiveRound,
                    total: effectiveRoundsTotal,
                    active:
                        view.status == TimerStatus.running ||
                        view.status == TimerStatus.paused,
                    done: view.status == TimerStatus.done,
                    phaseColor: phaseColor,
                  ),
                ),

              _CornerButton(
                alignment: Alignment.topLeft,
                label: '簿',
                faded: view.status == TimerStatus.running,
                onTap: () => _openPage(StatsPage(controller: controller)),
              ),
              _CornerButton(
                alignment: Alignment.topRight,
                label: '···',
                faded: view.status == TimerStatus.running,
                onTap: () => _openPage(SettingsPage(controller: controller)),
              ),
              Positioned.fill(
                child: GlobalNav(
                  current: GlobalNavDestination.focus,
                  todoCount: controller.doingTodos.length,
                  dim: view.status == TimerStatus.running,
                  onFocus: () {},
                  onGoals: () => unawaited(_openTodos()),
                ),
              ),

              if (_holdProgress > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      color: palette.work.withValues(
                        alpha: 0.06 * _holdProgress,
                      ),
                    ),
                  ),
                ),

              if (view.status == TimerStatus.paused)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(0, -0.1),
                          radius: 0.8,
                          colors: [
                            Colors.transparent,
                            palette.paper.withValues(alpha: 0.60),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              if (view.status == TimerStatus.done)
                _DoneLayer(
                  controller: controller,
                  template: template,
                  orbSize: orbSize,
                ),

              if (_showGuide)
                Positioned.fill(child: _GuideOverlay(onDismiss: _dismissGuide)),

              if (controller.notice != null)
                Positioned(
                  left: 28,
                  right: 28,
                  bottom: 86,
                  child: _Notice(text: controller.notice!),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

const double _focusContentCenterFraction = 0.43;
const double _globalNavClearance = 82;

/// 首页主视觉（球体、球内文字与球下提示）的统一纵向重心。
/// 只移动专注内容，不影响顶部入口与底部全局导航。
double _focusContentCenterY(Size size) =>
    size.height * _focusContentCenterFraction;

/// 完成态原本需要腾出的纵向距离，由球体向上与下方详情向下各承担一半。
double _doneSplitShiftY(Size size) {
  final normal = _focusContentCenterY(size);
  final targetUpperBound = normal - math.min(44.0, size.height * 0.12);
  final targetLowerBound = math.min(190.0, targetUpperBound);
  final fullUpwardTarget = (size.height * 0.30).clamp(
    targetLowerBound,
    targetUpperBound,
  );
  return math.max(0, normal - fullUpwardTarget) * 0.5;
}

double _orbCenterY(Size size, {required bool done}) {
  final normal = _focusContentCenterY(size);
  if (!done) return normal;
  return normal - _doneSplitShiftY(size);
}

/// 阶段点始终位于底部导航之上；矮屏略收紧间距。
double _roundStonesBottom(Size size) =>
    size.height < 700 ? _globalNavClearance : 88;

class _IdleTemplateCard extends StatelessWidget {
  const _IdleTemplateCard({
    required this.template,
    required this.pressed,
    required this.onOpenTemplates,
    required this.growthLevel,
  });

  final TimerTemplate? template;
  final bool pressed;
  final VoidCallback onOpenTemplates;
  final int growthLevel;

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    final compiled = _safeCompile(template);
    final roundsTotal = compiled.lastOrNull?.roundsTotal ?? 1;
    final size = MediaQuery.sizeOf(context);
    final contentCenterY = _focusContentCenterY(size);
    final orbSize = math.min(
      340.0,
      math.min(size.width * 0.74, math.min(size.width, size.height) * 0.68),
    );
    const idleView = TimerViewState.idle();
    final time = _timeText(template, compiled, idleView);
    final phase = _phaseWord(template, compiled, idleView);
    final round = _roundWord(idleView, 1, roundsTotal);

    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: contentCenterY - math.min(size.width * 0.72, 520) * 0.5,
          child: IgnorePointer(
            child: Text(
              '動',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'NotoSerifSC',
                fontSize: math.min(size.width * 0.72, 520),
                fontWeight: FontWeight.w200,
                height: 1,
                color: palette.work.withValues(alpha: 0.05),
              ).variableWeight,
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: contentCenterY - orbSize * 0.5,
          child: IgnorePointer(
            child: Center(
              child: SizedBox(
                width: orbSize,
                height: orbSize,
                child: BreathOrb(
                  progress: 0,
                  resting: false,
                  paused: false,
                  pressed: pressed,
                  growthLevel: growthLevel,
                  time: time,
                  phase: phase,
                  round: round,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 24,
          left: 70,
          right: 70,
          child: _TemplateMenuHeader(
            template: template,
            enabled: true,
            showSwitchHint:
                template != null && template!.kind != TemplateKind.pomodoro,
            onPressed: onOpenTemplates,
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: contentCenterY + orbSize * 0.5 + 22,
          child: IgnorePointer(
            child: Text(
              template == null ? '点 上 方 新 建 一 枚 编 排' : '双 击 开 始',
              textAlign: TextAlign.center,
              style: inkText(
                context,
                size: 12,
                color: palette.inkSoft,
                spacing: 5,
              ),
            ),
          ),
        ),
        if (roundsTotal > 1)
          Positioned(
            left: 80,
            right: 80,
            bottom: 82,
            child: _RoundStones(
              round: 1,
              total: roundsTotal,
              active: false,
              done: false,
              phaseColor: palette.work,
            ),
          ),
      ],
    );
  }
}

class _TemplateMenuHeader extends StatelessWidget {
  const _TemplateMenuHeader({
    required this.template,
    required this.enabled,
    required this.onPressed,
    this.showSwitchHint = false,
  });

  final TimerTemplate? template;
  final bool enabled;
  final bool showSwitchHint;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    return Column(
      children: [
        Semantics(
          button: true,
          enabled: enabled,
          label: '专 注 编 排',
          child: InkWell(
            key: const ValueKey('template-menu-entry'),
            onTap: enabled ? onPressed : null,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      template?.label ?? '无 编 排',
                      key: const ValueKey('template-menu-title'),
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      textAlign: TextAlign.center,
                      style: inkText(
                        context,
                        size: 15,
                        color: enabled ? palette.ink : palette.inkSoft,
                        spacing: 5.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  SizedBox(
                    key: const ValueKey('template-menu-indicator'),
                    width: 18,
                    height: 22,
                    child: Center(
                      child: Transform.translate(
                        offset: const Offset(0, -0.5),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 16,
                          color: enabled ? palette.ink : palette.inkSoft,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _templateSubtitle(template),
          style: TextStyle(
            fontFamily: 'Cormorant',
            fontSize: 12,
            color: palette.inkSoft,
            letterSpacing: 4.2,
          ).variableWeight,
        ),
        if (showSwitchHint) ...[
          const SizedBox(height: 6),
          Text(
            '轻 点 上 方 · 切 换 编 排',
            key: const ValueKey('template-switch-hint'),
            style: inkText(
              context,
              size: 11,
              color: palette.inkSoft.withValues(alpha: 0.72),
              spacing: 2.4,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Container(
          width: 1,
          height: showSwitchHint ? 18 : 26,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [palette.inkFaint, Colors.transparent],
            ),
          ),
        ),
      ],
    );
  }
}

List<Phase> _safeCompile(TimerTemplate? template) {
  if (template == null || template.kind == TemplateKind.accumulate) {
    return const [];
  }
  try {
    return compileTemplate(template);
  } on Object {
    return const [];
  }
}

String _formatTimer(int seconds) {
  final safe = math.max(0, seconds);
  return '${safe ~/ 60}:${(safe % 60).toString().padLeft(2, '0')}';
}

String _timeText(
  TimerTemplate? template,
  List<Phase> compiled,
  TimerViewState view,
) {
  if (view.status == TimerStatus.running || view.status == TimerStatus.paused) {
    return _formatTimer(view.remainSec);
  }
  if (view.status == TimerStatus.done) {
    return template?.kind == TemplateKind.accumulate
        ? _formatTimer(view.remainSec)
        : '0:00';
  }
  if (template == null) return '--:--';
  return _formatTimer(
    template.kind == TemplateKind.accumulate
        ? 0
        : (compiled.firstOrNull?.durationSec ?? 0),
  );
}

const _kindWords = {
  TemplateKind.pomodoro: '专 注',
  TemplateKind.interval: '动 作',
  TemplateKind.accumulate: '积 累',
};

const _roleWords = {
  SequencePhaseRole.focus: '专 注',
  SequencePhaseRole.work: '动 作',
  SequencePhaseRole.rest: '休 息',
  SequencePhaseRole.prepare: '准 备',
};

String _phaseWord(
  TimerTemplate? template,
  List<Phase> compiled,
  TimerViewState view,
) {
  if (view.status == TimerStatus.done) return '圆 成';
  if (view.status == TimerStatus.running || view.status == TimerStatus.paused) {
    final phase = view.phase;
    if (phase?.kind == PhaseKind.longRest) return '长 休';
    if (phase?.role != null) return _roleWords[phase!.role]!;
    return phase?.kind == PhaseKind.rest
        ? '休 息'
        : (_kindWords[template?.kind] ?? '动 作');
  }
  return compiled.firstOrNull?.role != null
      ? _roleWords[compiled.first.role]!
      : (_kindWords[template?.kind] ?? '动 作');
}

const _numbers = ['一', '二', '三', '四', '五', '六', '七', '八', '九', '十'];

String _cn(int value) => value >= 1 && value <= _numbers.length
    ? _numbers[value - 1]
    : value.toString();

String _roundWord(TimerViewState view, int round, int total) {
  if (view.status == TimerStatus.done) return '';
  if (view.status == TimerStatus.paused) return '双 击 继 续';
  return total <= 1 ? '持 续 中' : '第${_cn(round)}组 · 共${_cn(total)}组';
}

String _templateSubtitle(TimerTemplate? template) {
  if (template == null) return '';
  if (template.kind == TemplateKind.accumulate) return '积 累';
  if (template.sequence?.isNotEmpty ?? false) {
    return '编 排 · ${template.sequence!.length}段 × ${template.rounds ?? 1}';
  }
  if (template.kind == TemplateKind.interval) {
    return template.phases != null && template.phases!.length > 1
        ? '间 歇 · 自定义 × ${template.rounds ?? 1}'
        : '间 歇 · ${_cn(template.rounds ?? 1)}组';
  }
  return 'POMODORO · ${_cn(template.rounds ?? 1)}组';
}

class _CornerButton extends StatelessWidget {
  const _CornerButton({
    required this.alignment,
    required this.label,
    required this.faded,
    required this.onTap,
  });

  final Alignment alignment;
  final String label;
  final bool faded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    final left = alignment.x < 0;
    final top = alignment.y < 0;
    return Positioned(
      left: left ? 14 : null,
      right: left ? null : 14,
      top: top ? 6 : null,
      bottom: top ? null : 10,
      child: Semantics(
        button: true,
        label: label,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 58,
            height: 58,
            child: Align(
              alignment: alignment,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  label,
                  style: inkText(
                    context,
                    size: label == '···' ? 12 : 14,
                    color: faded ? palette.inkFaint : palette.inkSoft,
                    spacing: 2,
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

class _RoundStones extends StatelessWidget {
  const _RoundStones({
    required this.round,
    required this.total,
    required this.active,
    required this.done,
    required this.phaseColor,
  });

  final int round;
  final int total;
  final bool active;
  final bool done;
  final Color phaseColor;

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < total; index++) ...[
                AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done || index < round - 1
                        ? palette.ink
                        : Colors.transparent,
                    border: Border.all(
                      color: active && index == round - 1
                          ? phaseColor
                          : palette.inkFaint,
                    ),
                    boxShadow: active && index == round - 1
                        ? [
                            BoxShadow(
                              color: phaseColor.withValues(alpha: 0.15),
                              spreadRadius: 6,
                            ),
                          ]
                        : null,
                  ),
                ),
                if (index < total - 1) const SizedBox(width: 14),
              ],
            ],
          ),
        ),
        const SizedBox(height: 15),
        Text(
          'ROUNDS',
          style: TextStyle(
            fontSize: 11,
            color: palette.inkSoft,
            letterSpacing: 4,
          ),
        ),
      ],
    );
  }
}

String _qualityCauseText(SessionGrowthFeedback feedback) {
  final causes = <String>[
    if (feedback.evidence.backgroundExcursionCount > 0)
      '离席 ${feedback.evidence.backgroundExcursionCount}',
    if (feedback.evidence.manualPauseCount > 0)
      '暂停 ${feedback.evidence.manualPauseCount}',
    if (feedback.evidence.inAppDiversionCount > 0)
      '分心 ${feedback.evidence.inAppDiversionCount}',
    if (feedback.evidence.canceledHoldCount > 0)
      '触钟 ${feedback.evidence.canceledHoldCount}',
  ];
  return causes.isEmpty ? '心绪安定' : causes.join(' · ');
}

class _DoneLayer extends StatefulWidget {
  const _DoneLayer({
    required this.controller,
    required this.template,
    required this.orbSize,
  });

  final AppController controller;
  final TimerTemplate? template;
  final double orbSize;

  @override
  State<_DoneLayer> createState() => _DoneLayerState();
}

class _DoneLayerState extends State<_DoneLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _insightFade;
  Timer? _insightTimer;

  @override
  void initState() {
    super.initState();
    _insightFade = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _checkInsightNotice();
  }

  @override
  void didUpdateWidget(_DoneLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _checkInsightNotice();
  }

  void _checkInsightNotice() {
    if (widget.controller.pendingInsightNotice != null) {
      _insightTimer?.cancel();
      _insightFade.forward(from: 0.0);
      _insightTimer = Timer(const Duration(milliseconds: 2500), () {
        if (mounted) {
          _insightFade.reverse().then((_) {
            if (mounted) {
              widget.controller.clearInsightNotice();
            }
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _insightTimer?.cancel();
    _insightFade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    final size = MediaQuery.sizeOf(context);
    final compiled = _safeCompile(widget.template);
    final detail = widget.template?.kind == TemplateKind.accumulate
        ? '${widget.template?.label ?? ''} · ${formatDuration(widget.controller.timer.remainSec)}'
        : '${widget.template?.label ?? ''} · ${compiled.lastOrNull?.roundsTotal ?? 1} ROUNDS · ${formatDuration(plannedDurationSec(compiled))}';
    final insights = widget.controller.pendingInsightNotice;
    final orbCenterY = _orbCenterY(size, done: true);
    final sealMaxSize = math.min(92.0, math.max(28.0, size.width - 24));
    final sealMinSize = math.min(72.0, sealMaxSize);
    final sealSize = (widget.orbSize * 0.27).clamp(sealMinSize, sealMaxSize);
    final sealMaxLeft = math.max(0.0, size.width - sealSize - 12);
    final sealMinLeft = math.min(12.0, sealMaxLeft);
    final sealLeft = (size.width / 2 + widget.orbSize * 0.20).clamp(
      sealMinLeft,
      sealMaxLeft,
    );
    final sealMaxTop = math.max(0.0, size.height - sealSize);
    final sealMinTop = math.min(76.0, sealMaxTop);
    final sealTop = (orbCenterY - widget.orbSize * 0.30).clamp(
      sealMinTop,
      sealMaxTop,
    );
    final detailsBottom = math.min(_globalNavClearance, size.height * 0.32);
    final maxDetailsTop = math.max(0.0, size.height - detailsBottom - 1);
    final desiredDetailsTop = math.max(
      orbCenterY + widget.orbSize * 0.5 + 12,
      size.height * 0.48,
    );
    final detailsTop = desiredDetailsTop.clamp(0.0, maxDetailsTop);
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: Stack(
          children: [
            AnimatedPositioned(
              key: const ValueKey('done-seal'),
              duration: const Duration(milliseconds: 760),
              curve: Curves.easeInOutCubic,
              left: sealLeft,
              top: sealTop,
              child: Transform.rotate(
                angle: -0.05,
                child: Container(
                  width: sealSize,
                  height: sealSize,
                  decoration: BoxDecoration(
                    color: const Color(0xffb43a1e),
                    borderRadius: BorderRadius.circular(sealSize * 0.11),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x59b43a1e),
                        blurRadius: 24,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '成',
                    style: TextStyle(
                      fontFamily: 'NotoSerifSC',
                      fontWeight: FontWeight.w600,
                      fontSize: sealSize * 0.48,
                      color: const Color(0xfff6efe2),
                    ).variableWeight,
                  ),
                ),
              ),
            ),
            Positioned(
              key: const ValueKey('done-details-region'),
              top: detailsTop,
              left: 24,
              right: 24,
              bottom: detailsBottom,
              child: SingleChildScrollView(
                key: const ValueKey('done-details'),
                padding: EdgeInsets.only(
                  bottom: MediaQuery.paddingOf(context).bottom + 12,
                ),
                physics: const BouncingScrollPhysics(),
                child: Column(
                  children: [
                    Text(
                      '功 课 已 毕',
                      style: inkText(context, size: 14, spacing: 6),
                    ),
                    if (insights != null && insights.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      FadeTransition(
                        opacity: _insightFade,
                        child: Text(
                          insights.map((i) => '悟 · ${i.name}').join(' · '),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'Cormorant',
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: Color(0xffd4a574),
                            letterSpacing: 1.5,
                          ).variableWeight,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    if (widget.controller.sessionGrowthFeedback
                        case final feedback?) ...[
                      Text(
                        '定 ${feedback.qualityScore} · 本次 +${feedback.awardedExp}',
                        key: const ValueKey('session-growth-feedback'),
                        textAlign: TextAlign.center,
                        style: inkText(
                          context,
                          size: 13,
                          color: palette.work,
                          spacing: 2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _qualityCauseText(feedback),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: palette.inkSoft),
                      ),
                      if (feedback.leveledUp) ...[
                        const SizedBox(height: 4),
                        Text(
                          '隐 修 ${feedback.oldLevel} → ${feedback.newLevel}',
                          key: const ValueKey('level-up-feedback'),
                          style: TextStyle(fontSize: 11, color: palette.gold),
                        ),
                      ],
                      const SizedBox(height: 5),
                    ],
                    Text(
                      widget.controller.timer.interruptions > 0
                          ? '$detail · 打断 ${widget.controller.timer.interruptions}'
                          : detail,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: palette.inkSoft,
                        letterSpacing: 3,
                      ),
                    ),
                    if (widget.controller.doingTodos.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      TextButton(
                        key: const ValueKey('link-session-todo'),
                        onPressed: () =>
                            _showTodoLinkSheet(context, widget.controller),
                        child: Text(
                          '专注于',
                          style: inkText(context, size: 13, spacing: 2),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    _FeelingRow(controller: widget.controller),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeelingRow extends StatelessWidget {
  const _FeelingRow({required this.controller});

  final AppController controller;

  static const _options = <(SessionFeeling, String)>[
    (SessionFeeling.arduous, '艰'),
    (SessionFeeling.smooth, '顺'),
    (SessionFeeling.transcendent, '透'),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    final current = controller.lastSession?.feeling;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final (feeling, label) in _options)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: Semantics(
              button: true,
              selected: current == feeling,
              child: InkWell(
                key: ValueKey('feeling-${feeling.wire}'),
                onTap: () => controller.setLastSessionFeeling(feeling),
                borderRadius: BorderRadius.circular(24),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: current == feeling
                        ? palette.ink.withValues(alpha: 0.07)
                        : null,
                    border: Border.all(
                      color: current == feeling
                          ? palette.ink.withValues(alpha: 0.34)
                          : palette.inkFaint,
                    ),
                  ),
                  child: Text(
                    label,
                    style: inkText(
                      context,
                      size: 13,
                      color: current == feeling ? palette.ink : palette.inkSoft,
                      spacing: 0,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

Future<void> _showTodoLinkSheet(
  BuildContext context,
  AppController controller,
) async {
  final todos = controller.doingTodos;
  if (todos.isEmpty) return;
  var selected = controller.lastSession?.linkedTodoId;
  if (!todos.any((todo) => todo.id == selected)) selected = todos.first.id;
  int? amount;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => StatefulBuilder(
      builder: (context, setModalState) {
        final palette = ZenPalette.of(context);
        return Container(
          padding: EdgeInsets.fromLTRB(
            28,
            22,
            28,
            28 + MediaQuery.paddingOf(context).bottom,
          ),
          decoration: BoxDecoration(
            color: palette.paper,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(top: BorderSide(color: palette.inkFaint)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('专 注 于', style: inkText(context, size: 13, spacing: 5)),
                const SizedBox(height: 8),
                Text(
                  '关 联 本 次 投 入 · 可 选 记 入 清 单 进 度',
                  style: inkText(
                    context,
                    size: 12,
                    color: palette.inkSoft,
                    spacing: 2,
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final todo in todos)
                      ChoiceChip(
                        key: ValueKey('link-todo-${todo.id}'),
                        selected: selected == todo.id,
                        label: Text(todo.text.split('\n').first),
                        onSelected: (_) =>
                            setModalState(() => selected = todo.id),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      key: const ValueKey('todo-progress-none'),
                      selected: amount == null,
                      label: const Text('不 记 进 度'),
                      onSelected: (_) => setModalState(() => amount = null),
                    ),
                    for (final value in [1, 5, 25, 50, 100])
                      ChoiceChip(
                        key: ValueKey('todo-progress-$value'),
                        selected: amount == value,
                        label: Text('+$value'),
                        onSelected: (_) => setModalState(() => amount = value),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                TextButton(
                  key: const ValueKey('confirm-session-todo'),
                  onPressed: () async {
                    await controller.applyLastSessionToTodo(
                      selected!,
                      progressAmount: amount?.toDouble(),
                    );
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: Text('收', style: inkText(context, spacing: 4)),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    '不 关 联',
                    style: inkText(context, color: palette.inkSoft, spacing: 3),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _GuideOverlay extends StatelessWidget {
  const _GuideOverlay({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    return Material(
      color: palette.paper.withValues(alpha: 0.94),
      child: InkWell(
        onTap: onDismiss,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 34),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _guideLine(context, '双 击', '开始 / 暂停（球球上）'),
                _guideLine(context, '长 按', '提前结束'),
                _guideLine(context, '上 方', '切换专注编排'),
                const SizedBox(height: 12),
                Text(
                  '专注 计时　目标 清单　簿 功课　··· 设置',
                  textAlign: TextAlign.center,
                  style: inkText(
                    context,
                    size: 11,
                    color: palette.inkSoft,
                    spacing: 2.5,
                  ),
                ),
                const SizedBox(height: 34),
                TextButton(
                  onPressed: onDismiss,
                  child: Text('知 道 了', style: inkText(context, spacing: 5)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _guideLine(BuildContext context, String action, String description) {
    final palette = ZenPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: action,
              style: inkText(context, size: 12, spacing: 4),
            ),
            TextSpan(
              text: ' · $description',
              style: inkText(
                context,
                size: 11,
                color: palette.inkSoft,
                spacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = ZenPalette.of(context);
    return Material(
      color: palette.paperDeep.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(3),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: inkText(context, size: 12, color: palette.inkSoft, spacing: 3),
        ),
      ),
    );
  }
}
