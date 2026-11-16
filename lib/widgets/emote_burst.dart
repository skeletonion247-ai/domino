import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A floating text emote ("HA HA HA", "GG WP") rising from a seat.
class EmoteBurst {
  EmoteBurst._();

  static const int durationMs = 1300;

  static EmoteBurstRun? play({
    required BuildContext context,
    required TickerProvider vsync,
    required Offset at,
    required String text,
    Color color = const Color(0xFFFFD84D),
  }) {
    final overlay = Overlay.of(context);
    final controller = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: durationMs),
    );
    final entry = OverlayEntry(
      builder: (_) => IgnorePointer(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final t = controller.value;
            final rise = 58 * Curves.easeOut.transform(t);
            final fade = t < 0.15
                ? t / 0.15
                : (t > 0.7 ? 1 - (t - 0.7) / 0.3 : 1.0);
            final pop = t < 0.3
                ? Curves.easeOutBack.transform((t / 0.3).clamp(0.0, 1.0))
                : 1.0;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: at.dx - 90,
                  top: at.dy - 46 - rise,
                  width: 180,
                  child: Opacity(
                    opacity: fade.clamp(0.0, 1.0),
                    child: Transform.rotate(
                      angle: math.sin(t * 9) * 0.04,
                      child: Transform.scale(
                        scale: 0.6 + 0.45 * pop,
                        child: Text(
                          text,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: color,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            shadows: const [
                              Shadow(
                                color: Color(0xCC000000),
                                blurRadius: 0,
                                offset: Offset(2, 2),
                              ),
                              Shadow(color: Colors.black54, blurRadius: 8),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    overlay.insert(entry);
    final run = EmoteBurstRun._(controller, entry);
    controller.forward(from: 0).whenCompleteOrCancel(run._finish);
    return run;
  }
}

/// Handle to one running burst.
class EmoteBurstRun {
  EmoteBurstRun._(this._controller, this._entry);

  final AnimationController _controller;
  OverlayEntry? _entry;
  final Completer<void> _done = Completer<void>();
  bool _closed = false;

  Future<void> get done => _done.future;

  void _finish() {
    if (_closed) return;
    _closed = true;
    try {
      if (_entry?.mounted ?? false) _entry!.remove();
    } catch (_) {}
    _entry = null;
    _controller.dispose();
    if (!_done.isCompleted) _done.complete();
  }

  void dispose() => _finish();
}
