import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Continuous zoom without Material Slider's full-page value-indicator overlay.
/// The current zoom remains visible beside this control.
class CanvasZoomControl extends StatefulWidget {
  const CanvasZoomControl(
      {super.key,
      required this.value,
      required this.color,
      required this.onChanged,
      required this.formatValue});
  final double value;
  final Color color;
  final ValueChanged<double> onChanged;
  final String Function(double) formatValue;

  @override
  State<CanvasZoomControl> createState() => _CanvasZoomControlState();
}

class _CanvasZoomControlState extends State<CanvasZoomControl> {
  final _focus = FocusNode(debugLabel: 'Canvas zoom');
  int? _activePointer;

  void _pointAt(double x, double width) {
    const inset = 8.0 + CupertinoThumbPainter.radius;
    final position = (x - inset) / (width - 2 * inset);
    widget.onChanged(_bounded(Directionality.of(context) == TextDirection.rtl
        ? 1 - position
        : position));
  }

  double _bounded(double value) => value.clamp(0.0, 1.0);
  void _adjust(double delta) =>
      widget.onChanged(_bounded(widget.value + delta));

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowDown) {
      _adjust(key == LogicalKeyboardKey.arrowLeft &&
              Directionality.of(context) == TextDirection.rtl
          ? 0.02
          : -0.02);
    } else if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowUp) {
      _adjust(key == LogicalKeyboardKey.arrowRight &&
              Directionality.of(context) == TextDirection.rtl
          ? -0.02
          : 0.02);
    } else if (key == LogicalKeyboardKey.home) {
      widget.onChanged(0);
    } else if (key == LogicalKeyboardKey.end) {
      widget.onChanged(1);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Zoom',
        slider: true,
        focusable: true,
        focused: _focus.hasFocus,
        value: widget.formatValue(widget.value),
        increasedValue: widget.formatValue(_bounded(widget.value + 0.02)),
        decreasedValue: widget.formatValue(_bounded(widget.value - 0.02)),
        onIncrease: () => _adjust(0.02),
        onDecrease: () => _adjust(-0.02),
        onDidGainAccessibilityFocus: _focus.requestFocus,
        child: ExcludeSemantics(
            child: Focus(
          focusNode: _focus,
          includeSemantics: false,
          onKeyEvent: _onKey,
          onFocusChange: (_) => setState(() {}),
          child: LayoutBuilder(
              builder: (context, constraints) => Listener(
                    key: const ValueKey('canvas-zoom-slider'),
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (event) {
                      if (_activePointer != null || event.buttons != 1) return;
                      _activePointer = event.pointer;
                      _focus.requestFocus();
                      _pointAt(event.localPosition.dx, constraints.maxWidth);
                    },
                    onPointerMove: (event) {
                      if (_activePointer == event.pointer) {
                        _pointAt(event.localPosition.dx, constraints.maxWidth);
                      }
                    },
                    onPointerUp: (event) {
                      if (_activePointer == event.pointer) {
                        _activePointer = null;
                      }
                    },
                    onPointerCancel: (event) {
                      if (_activePointer == event.pointer) {
                        _activePointer = null;
                      }
                    },
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: _focus.hasFocus
                                  ? widget.color
                                  : Colors.transparent,
                              width: 2)),
                      child: SizedBox(
                          height: 44,
                          child: IgnorePointer(
                              child: CupertinoSlider(
                            value: widget.value,
                            activeColor: widget.color,
                            thumbColor: widget.color,
                            onChanged: widget.onChanged,
                          ))),
                    ),
                  )),
        )),
      );
}
