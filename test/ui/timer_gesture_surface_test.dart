import 'dart:ui' show SemanticsAction;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uptimer/ui/home/timer_gesture_surface.dart';

Widget _surface({
  required VoidCallback onDoubleTap,
  required ValueChanged<bool> onPressedChanged,
  VoidCallback? onHoldDown,
  VoidCallback? onHoldRecognized,
  VoidCallback? onHoldEnd,
  VoidCallback? onRecognizedHoldReleased,
  String? semanticLabel,
  VoidCallback? onSemanticTap,
  VoidCallback? onSemanticLongPress,
}) => MaterialApp(
  home: Scaffold(
    body: TimerGestureSurface(
      key: const ValueKey('gesture-surface'),
      onDoubleTap: onDoubleTap,
      onPressedChanged: onPressedChanged,
      onHoldDown: onHoldDown,
      onHoldRecognized: onHoldRecognized,
      onHoldEnd: onHoldEnd,
      onRecognizedHoldReleased: onRecognizedHoldReleased,
      semanticLabel: semanticLabel,
      onSemanticTap: onSemanticTap,
      onSemanticLongPress: onSemanticLongPress,
      child: const SizedBox.expand(child: ColoredBox(color: Colors.white)),
    ),
  ),
);

Future<void> _mouseTap(
  WidgetTester tester,
  Offset position, {
  int pointer = 1,
}) async {
  final gesture = await tester.createGesture(
    pointer: pointer,
    kind: PointerDeviceKind.mouse,
  );
  await gesture.down(position);
  await tester.pump(const Duration(milliseconds: 24));
  await gesture.up();
}

void main() {
  testWidgets('鼠标与触控共用原始指针双击，横移不会被误判为点击', (tester) async {
    var doubleTaps = 0;
    final pressed = <bool>[];
    await tester.pumpWidget(
      _surface(
        onDoubleTap: () => doubleTaps += 1,
        onPressedChanged: pressed.add,
      ),
    );
    final center = tester.getCenter(
      find.byKey(const ValueKey('gesture-surface')),
    );

    await _mouseTap(tester, center, pointer: 1);
    await tester.pump(const Duration(milliseconds: 80));
    await _mouseTap(tester, center, pointer: 2);
    await tester.pump();
    expect(doubleTaps, 1);

    final drag = await tester.createGesture(
      pointer: 3,
      kind: PointerDeviceKind.touch,
    );
    await drag.down(center);
    await drag.moveBy(const Offset(72, 3));
    await drag.up();
    await tester.pump(const Duration(milliseconds: 80));
    await _mouseTap(tester, center, pointer: 4);
    await tester.pump();

    expect(doubleTaps, 1);
    expect(pressed.last, isFalse);
  });

  testWidgets('长按发生明显位移后立即取消且不会延迟触发', (tester) async {
    var holdDown = 0;
    var holdRecognized = 0;
    var holdEnd = 0;
    await tester.pumpWidget(
      _surface(
        onDoubleTap: () {},
        onPressedChanged: (_) {},
        onHoldDown: () => holdDown += 1,
        onHoldRecognized: () => holdRecognized += 1,
        onHoldEnd: () => holdEnd += 1,
      ),
    );
    final center = tester.getCenter(
      find.byKey(const ValueKey('gesture-surface')),
    );
    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 180));
    await gesture.moveBy(const Offset(36, 2));
    await tester.pump(const Duration(milliseconds: 520));

    expect(holdDown, 1);
    expect(holdRecognized, 0);
    expect(holdEnd, 1);
    await gesture.up();
    expect(holdEnd, 1);
  });

  testWidgets('只有识别后的正常释放才记为取消长按', (tester) async {
    var released = 0;
    await tester.pumpWidget(
      _surface(
        onDoubleTap: () {},
        onPressedChanged: (_) {},
        onHoldDown: () {},
        onHoldRecognized: () {},
        onHoldEnd: () {},
        onRecognizedHoldReleased: () => released += 1,
      ),
    );
    final center = tester.getCenter(
      find.byKey(const ValueKey('gesture-surface')),
    );

    final normal = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 520));
    await normal.up();
    expect(released, 1);

    final moved = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 520));
    await moved.moveBy(const Offset(40, 0));
    await moved.up();
    expect(released, 1);

    final canceled = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 520));
    await canceled.cancel();
    expect(released, 1);
  });

  testWidgets('语义点击与长按可触发核心计时动作', (tester) async {
    var semanticTaps = 0;
    var semanticLongPresses = 0;
    await tester.pumpWidget(
      _surface(
        onDoubleTap: () {},
        onPressedChanged: (_) {},
        semanticLabel: '开始专注',
        onSemanticTap: () => semanticTaps += 1,
        onSemanticLongPress: () => semanticLongPresses += 1,
      ),
    );
    final semantics = tester.ensureSemantics();
    final node = tester.getSemantics(
      find.byKey(const ValueKey('gesture-surface')),
    );
    expect(node.label, contains('开始专注'));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(
      node.getSemanticsData().hasAction(SemanticsAction.longPress),
      isTrue,
    );

    tester.semantics.tap(find.semantics.byLabel('开始专注'));
    tester.semantics.longPress(find.semantics.byLabel('开始专注'));
    await tester.pump();

    expect(semanticTaps, 1);
    expect(semanticLongPresses, 1);
    semantics.dispose();
  });
}
