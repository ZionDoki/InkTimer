import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/gestures.dart';

/// Passively observes raw pointer events without entering Flutter's gesture
/// arena, keeping double-tap and hold recognition independent and stable.
class TimerGestureSurface extends StatefulWidget {
  const TimerGestureSurface({
    super.key,
    required this.child,
    required this.onDoubleTap,
    required this.onPressedChanged,
    this.onHoldDown,
    this.onHoldRecognized,
    this.onHoldEnd,
    this.onRecognizedHoldReleased,
    this.semanticLabel,
    this.onSemanticTap,
    this.onSemanticLongPress,
    this.movementSlop = 18,
    this.holdRecognitionDelay = const Duration(milliseconds: 500),
  });

  final Widget child;
  final VoidCallback onDoubleTap;
  final ValueChanged<bool> onPressedChanged;
  final VoidCallback? onHoldDown;
  final VoidCallback? onHoldRecognized;
  final VoidCallback? onHoldEnd;
  final VoidCallback? onRecognizedHoldReleased;
  final String? semanticLabel;
  final VoidCallback? onSemanticTap;
  final VoidCallback? onSemanticLongPress;
  final double movementSlop;
  final Duration holdRecognitionDelay;

  @override
  State<TimerGestureSurface> createState() => _TimerGestureSurfaceState();
}

class _TimerGestureSurfaceState extends State<TimerGestureSurface> {
  final DoubleTapGuard _doubleTap = DoubleTapGuard(windowMs: 420, radiusPx: 48);

  int? _pointer;
  Offset _downPosition = Offset.zero;
  bool _moved = false;
  bool _pressed = false;
  bool _holdStarted = false;
  bool _holdRecognized = false;
  bool _holdEnded = false;
  Timer? _recognitionTimer;

  bool get _holdEnabled =>
      widget.onHoldDown != null ||
      widget.onHoldRecognized != null ||
      widget.onHoldEnd != null;

  @override
  void dispose() {
    _recognitionTimer?.cancel();
    super.dispose();
  }

  void _setPressed(bool value) {
    if (_pressed == value) return;
    _pressed = value;
    widget.onPressedChanged(value);
  }

  void _pointerDown(PointerDownEvent event) {
    if (_pointer != null) {
      _cancelCurrent(resetDoubleTap: true);
      return;
    }
    _pointer = event.pointer;
    _downPosition = event.position;
    _moved = false;
    _holdStarted = _holdEnabled;
    _holdRecognized = false;
    _holdEnded = false;
    _setPressed(true);

    if (!_holdEnabled) return;
    widget.onHoldDown?.call();
    _recognitionTimer?.cancel();
    _recognitionTimer = Timer(widget.holdRecognitionDelay, () {
      if (!mounted || _pointer == null || _moved || _holdEnded) return;
      _holdRecognized = true;
      _doubleTap.reset();
      widget.onHoldRecognized?.call();
    });
  }

  void _pointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer || _moved) return;
    if ((event.position - _downPosition).distance <= widget.movementSlop) {
      return;
    }
    _moved = true;
    _doubleTap.reset();
    _setPressed(false);
    _endHold();
  }

  void _pointerUp(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    final countsAsTap = !_moved && !_holdRecognized;
    _recognitionTimer?.cancel();
    _recognitionTimer = null;
    _setPressed(false);
    final recognizedReleasedNormally = _holdRecognized && !_moved;
    _endHold();
    _pointer = null;
    if (recognizedReleasedNormally) {
      widget.onRecognizedHoldReleased?.call();
    }

    if (!countsAsTap) {
      _doubleTap.reset();
      return;
    }
    if (_doubleTap.tap(
      event.position.dx,
      event.position.dy,
      event.timeStamp.inMilliseconds,
    )) {
      widget.onDoubleTap();
    }
  }

  void _pointerCancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    _cancelCurrent(resetDoubleTap: true);
  }

  void _endHold() {
    _recognitionTimer?.cancel();
    _recognitionTimer = null;
    if (!_holdStarted || _holdEnded) return;
    _holdEnded = true;
    widget.onHoldEnd?.call();
  }

  void _cancelCurrent({required bool resetDoubleTap}) {
    _recognitionTimer?.cancel();
    _recognitionTimer = null;
    _setPressed(false);
    _endHold();
    _pointer = null;
    _moved = false;
    if (resetDoubleTap) _doubleTap.reset();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.semanticLabel,
    button: widget.onSemanticTap != null || widget.onSemanticLongPress != null,
    onTap: widget.onSemanticTap,
    onLongPress: widget.onSemanticLongPress,
    child: Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _pointerDown,
      onPointerMove: _pointerMove,
      onPointerUp: _pointerUp,
      onPointerCancel: _pointerCancel,
      child: widget.child,
    ),
  );
}
