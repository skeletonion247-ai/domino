import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/arcade_ui.dart';

/// Little golden chips flying from the losing players to the winning team's
/// score counter at the end of a hand.
class ScoreFly {
  ScoreFly._();

  static const int durationMs = 900;

  static ScoreFlyRun? play({
    required BuildContext context,
    required TickerProvider vsync,
    required List<Offset> from,
    required Offset to,
    required int points,
    Color color = ArcadeColors.gold,
  }) {
    if (from.isEmpty || points <= 0) return null;
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
            final ms = controller.value * durationMs;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                for (var i = 0; i < 6; i++) _chip(from[i % from.length], to, i, ms, color),
                _label(to, points, ms),
              ],
            );
          },
        ),
      ),
    );
    overlay.insert(entry);
    final run = ScoreFlyRun._(controller, entry);
    controller.forward(from: 0).whenCompleteOrCancel(run._finish);
    return run;
  }

  static Widget _chip(Offset from, Offset to, int i, double ms, Color color) {
    final start = i * 55.0;
    final t = ((ms - start) / 620).clamp(0.0, 1.0);
    if (t <= 0) return const SizedBox.shrink();
    final p = Curves.easeInOutCubic.transform(t);
    final lift = 54 * math.sin(math.pi * p);
    final pos =
        Offset.lerp(from, to, p)! +
        Offset(
          math.sin(i * 2.1) * 14 * (1 - p),
          -lift + math.cos(i * 1.7) * 10 * (1 - p),
        );
    final fade = t > 0.82 ? 1 - (t - 0.82) / 0.18 : 1.0;
    const size = 16.0;
    return Positioned(
      left: pos.dx - size / 2,
      top: pos.dy - size / 2,
      width: size,
      height: size,
      child: Opacity(
        opacity: fade.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, color, ArcadeColors.goldDeep],
            ),
            border: Border.all(
              color: ArcadeColors.goldEdge.withValues(alpha: 0.8),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: 6,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _label(Offset to, int points, double ms) {
    final t = ((ms - 560) / 340).clamp(0.0, 1.0);
    if (t <= 0) return const SizedBox.shrink();
    final rise = 18.0 * t;
    return Positioned(
      left: to.dx - 40,
      top: to.dy - 34 - rise,
      width: 80,
      child: Opacity(
        opacity: (1 - t).clamp(0.0, 1.0),
        child: Text(
          '+$points',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: ArcadeColors.gold,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            shadows: [
              Shadow(color: Colors.black, blurRadius: 6),
              Shadow(color: Colors.black, blurRadius: 2),
            ],
          ),
        ),
      ),
    );
  }
}

/// Handle to one running burst. [dispose] stops it early and removes it.
class ScoreFlyRun {
  ScoreFlyRun._(this._controller, this._entry);

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
