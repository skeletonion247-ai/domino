import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/audio_service.dart';
import 'emote_picker.dart';

/// Throws a brick from your avatar to your partner's avatar: a hand rises,
/// grips the brick, winds up and chucks it. The brick flies with a trail,
/// BONK, dust and dizzy stars.
class BrickThrow {
  BrickThrow._();

  static const int durationMs = 1900;
  static const double _launchMs = 470;
  static const double _hitMs = 1040;

  static BrickThrowRun? play({
    required BuildContext context,
    required TickerProvider vsync,
    required Offset from,
    required Offset to,
  }) {
    final overlay = Overlay.of(context);
    final controller = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: durationMs),
    );
    final launchFrom = _grip(from, _launchMs);
    final entry = OverlayEntry(
      builder: (_) => IgnorePointer(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final ms = controller.value * durationMs;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                if (ms < 1000) _hand(from, ms),
                if (ms > _hitMs - 60 && ms < 1620) _ring(to, ms),
                if (ms > _hitMs - 60 && ms < 1540) _dust(to, ms),
                if (ms > _hitMs - 60 && ms < 1700) _dizzy(to, ms),
                if (ms > _hitMs - 80 && ms < 1640) _bonk(to, ms),
                if (ms < _launchMs) _heldBrick(from, ms),
                for (var i = 3; i >= 1; i--)
                  if (ms > _launchMs + i * 40 && ms < _hitMs)
                    _brickAt(launchFrom, to, ms - i * 40, ghost: i),
                if (ms >= _launchMs) _brickAt(launchFrom, to, ms),
              ],
            );
          },
        ),
      ),
    );
    overlay.insert(entry);
    final timers = <Timer>[
      Timer(const Duration(milliseconds: 430), () {
        AudioService.instance.playWhoosh();
      }),
      Timer(const Duration(milliseconds: 1020), () {
        AudioService.instance.playTonk();
      }),
    ];
    final run = BrickThrowRun._(controller, entry, timers);
    controller.forward(from: 0).whenCompleteOrCancel(run._finish);
    return run;
  }

  static (Offset pos, double angle) _handPose(Offset from, double ms) {
    if (ms < 240) {
      final p = Curves.easeOut.transform((ms / 240).clamp(0.0, 1.0));
      return (from + Offset(0, 48 * (1 - p)), -0.12);
    }
    if (ms < 460) {
      final p = ((ms - 240) / 220).clamp(0.0, 1.0);
      return (from + Offset(-7 * p, 0), -0.12 - 0.58 * p);
    }
    if (ms < 620) {
      final p = ((ms - 460) / 160).clamp(0.0, 1.0);
      return (from + Offset(-7 * (1 - p), 0), -0.70 + 0.95 * p);
    }
    final p = ((ms - 620) / 420).clamp(0.0, 1.0);
    return (from + Offset(0, 46 * p), 0.25);
  }

  static Offset _grip(Offset from, double ms) {
    final (pos, angle) = _handPose(from, ms);
    final v = Offset(-40 * math.sin(angle), -40 * math.cos(angle));
    return pos + v;
  }

  static double _handOpacity(double ms) {
    if (ms < 240) return (ms / 240).clamp(0.0, 1.0);
    if (ms < 620) return 1;
    return (1 - (ms - 620) / 380).clamp(0.0, 1.0);
  }

  static Widget _hand(Offset from, double ms) {
    final (pos, angle) = _handPose(from, ms);
    return Positioned(
      left: pos.dx - 32,
      top: pos.dy - 38,
      width: 64,
      height: 74,
      child: Opacity(
        opacity: _handOpacity(ms),
        child: Transform.rotate(
          angle: angle,
          child: const CustomPaint(painter: _HandPainter()),
        ),
      ),
    );
  }

  static Widget _heldBrick(Offset from, double ms) {
    final grip = _grip(from, ms);
    final (_, angle) = _handPose(from, ms);
    const width = 34.0;
    return Positioned(
      left: grip.dx - width / 2,
      top: grip.dy - width * 0.25,
      width: width,
      height: width * 0.5,
      child: Opacity(
        opacity: _handOpacity(ms).clamp(0.0, 1.0),
        child: Transform.rotate(
          angle: angle,
          child: const BrickView(width: width),
        ),
      ),
    );
  }

  static Widget _brickAt(
    Offset from,
    Offset to,
    double ms, {
    int ghost = 0,
  }) {
    const width = 34.0;
    final height = width * 0.5;
    Offset pos;
    double angle;
    double scale;
    double opacity = 1;

    if (ms < _hitMs) {
      final p = Curves.easeOut.transform(
        ((ms - _launchMs) / (_hitMs - _launchMs)).clamp(0.0, 1.0),
      );
      pos =
          Offset.lerp(from, to, p)! + Offset(0, -175 * 4 * p * (1 - p));
      angle = p * math.pi * 5;
      scale = 1.0 + 0.08 * math.sin(p * math.pi);
    } else if (ms < _hitMs + 150) {
      final p = ((ms - _hitMs) / 150).clamp(0.0, 1.0);
      pos = to + Offset(18 * p, -44 * math.sin(p * math.pi));
      angle = math.pi * 5 + p * 1.6;
      scale = 1.0;
    } else {
      final t = ((ms - _hitMs - 150) / 640).clamp(0.0, 1.0);
      pos = to + Offset(18 + 34 * t, 800 * t * t);
      angle = math.pi * 5 + 1.6 + t * 7;
      scale = 1.0;
      opacity = (1 - (t - 0.5).clamp(0.0, 1) / 0.5).clamp(0.0, 1.0);
    }

    if (ghost > 0) {
      opacity = (0.26 / ghost).clamp(0.0, 1.0);
      scale *= 0.94;
    }

    return Positioned(
      left: pos.dx - width / 2,
      top: pos.dy - height / 2,
      width: width,
      height: height,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform.rotate(
          angle: angle,
          child: Transform.scale(
            scale: scale,
            child: const BrickView(width: width),
          ),
        ),
      ),
    );
  }

  static Widget _ring(Offset to, double ms) {
    final t = ((ms - (_hitMs - 60)) / 600).clamp(0.0, 1.0);
    final size = 18 + 54 * Curves.easeOut.transform(t);
    return Positioned(
      left: to.dx - size / 2,
      top: to.dy - size / 2,
      width: size,
      height: size,
      child: Opacity(
        opacity: (1 - t).clamp(0.0, 1.0) * 0.8,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFFFFD84D),
              width: 3 * (1 - t) + 1,
            ),
          ),
        ),
      ),
    );
  }

  static Widget _dust(Offset to, double ms) {
    final t = ((ms - (_hitMs - 60)) / 540).clamp(0.0, 1.0);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (var i = 0; i < 7; i++)
          Positioned(
            left: to.dx + math.cos(i * 0.9 + 0.4) * (10 + 40 * t) - 3.5,
            top: to.dy + math.sin(i * 0.9 + 0.4) * (8 + 30 * t) - 3.5,
            width: 7,
            height: 7,
            child: Opacity(
              opacity: ((1 - t) * 0.55).clamp(0.0, 1.0),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFE8DCC8),
                ),
              ),
            ),
          ),
      ],
    );
  }

  static Widget _bonk(Offset to, double ms) {
    final t = ((ms - (_hitMs - 80)) / 560).clamp(0.0, 1.0);
    final pop = Curves.easeOutBack.transform((t * 2.4).clamp(0.0, 1.0));
    final fade = t < 0.6 ? 1.0 : 1 - (t - 0.6) / 0.4;
    return Positioned(
      left: to.dx - 64,
      top: to.dy - 78,
      width: 128,
      child: Opacity(
        opacity: fade.clamp(0.0, 1.0),
        child: Transform.rotate(
          angle: -0.18 + 0.05 * math.sin(t * 18),
          child: Transform.scale(
            scale: 0.45 + 0.75 * pop,
            child: const Text(
              'BONK!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFFFFD84D),
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
                shadows: [
                  Shadow(
                    color: Color(0xFF5A2015),
                    blurRadius: 0,
                    offset: Offset(2, 2),
                  ),
                  Shadow(color: Colors.black87, blurRadius: 6),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _dizzy(Offset to, double ms) {
    final t = ((ms - (_hitMs - 60)) / 800).clamp(0.0, 1.0);
    final opacity = t < 0.2 ? t / 0.2 : 1 - (t - 0.2) / 0.8;
    final centre = to - const Offset(0, 18);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (var i = 0; i < 3; i++)
          Positioned(
            left: centre.dx + math.cos(ms / 180 + i * 2.1) * 27 - 4,
            top: centre.dy + math.sin(ms / 180 + i * 2.1) * 11 - 4,
            width: 9,
            height: 9,
            child: Opacity(
              opacity: (opacity * 0.95).clamp(0.0, 1.0),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFFFD84D),
                  boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 3)],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Cartoon fist holding the brick.
class _HandPainter extends CustomPainter {
  const _HandPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final outline = Paint()
      ..color = const Color(0xFF6E3D22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final skin = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFE0C4), Color(0xFFF3BE92), Color(0xFFCB8452)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    final sleeve = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF42A5F5), Color(0xFF1565C0)],
      ).createShader(Rect.fromLTWH(0, h * 0.6, w, h * 0.4));

    // Cuff.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.16, h * 0.60, w * 0.68, h * 0.36),
        const Radius.circular(7),
      ),
      sleeve,
    );

    // Thumb behind the fist.
    canvas.save();
    canvas.translate(w * 0.20, h * 0.50);
    canvas.rotate(-0.55);
    final thumb = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: w * 0.26, height: h * 0.34),
      const Radius.circular(8),
    );
    canvas.drawRRect(thumb, skin);
    canvas.drawRRect(thumb, outline);
    canvas.restore();

    // Fist.
    final fist = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.12, h * 0.16, w * 0.74, h * 0.52),
      const Radius.circular(13),
    );
    canvas.drawRRect(fist, skin);
    canvas.drawRRect(fist, outline);

    // Knuckles.
    for (var i = 0; i < 4; i++) {
      final c = Offset(w * (0.22 + i * 0.19), h * 0.18);
      canvas.drawCircle(c, w * 0.11, skin);
      canvas.drawCircle(c, w * 0.11, outline);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Handle to one running throw.
class BrickThrowRun {
  BrickThrowRun._(this._controller, this._entry, this._timers);

  final AnimationController _controller;
  final List<Timer> _timers;
  OverlayEntry? _entry;
  final Completer<void> _done = Completer<void>();
  bool _closed = false;

  Future<void> get done => _done.future;

  void _finish() {
    if (_closed) return;
    _closed = true;
    for (final timer in _timers) {
      timer.cancel();
    }
    try {
      if (_entry?.mounted ?? false) _entry!.remove();
    } catch (_) {}
    _entry = null;
    _controller.dispose();
    if (!_done.isCompleted) _done.complete();
  }

  void dispose() => _finish();
}
