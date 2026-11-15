import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/domino_tile.dart';

/// Plays the end-of-hand reveal: every player's leftover tiles appear face-up
/// on their own side of the table, gather and shake in the middle, then fly
/// back into their hands.
///
/// Shared by practice and online. The caller owns the [TickerProvider] and
/// must [HandRevealRun.dispose] if it is torn down mid-animation.
class HandReveal {
  HandReveal._();

  static const double durationMs = 4600;

  /// [hands] is indexed by seat. [sideOfHand] maps a seat to a table side:
  /// 0 = bottom (you), 1 = left, 2 = top, 3 = right.
  static HandRevealRun? play({
    required BuildContext context,
    required TickerProvider vsync,
    required Rect table,
    required Rect? rack,
    required List<List<DominoTile>> hands,
    int Function(int seat) sideOfHand = _identitySide,
  }) {
    const scale = 0.4;
    const spriteW = 60.0 * scale;
    const spriteH = 130.0 * scale;
    final specs = <_RevealSpec>[];

    for (var seat = 0; seat < hands.length; seat++) {
      final tiles = List<DominoTile>.of(hands[seat]);
      if (tiles.isEmpty) continue;
      final side = sideOfHand(seat) % 4;
      final n = tiles.length;
      final row = side == 0 || side == 2;
      final across = row ? 130.0 * scale : 60.0 * scale;
      // The top row keeps clear of the seat avatar on the right.
      final room = side == 2
          ? math.max(across, table.width - 96)
          : row
          ? math.max(across, table.width - 28)
          : math.max(across, table.height * 0.68);
      final step = n > 1
          ? math.min(
              across + 2,
              math.max(across * 0.5, (room - across) / (n - 1)),
            )
          : across + 2;

      final Offset anchor;
      switch (side) {
        case 0:
          anchor = rack?.center ?? Offset(table.center.dx, table.bottom - 14);
          break;
        case 1:
          anchor = Offset(table.left + 30, table.center.dy);
          break;
        case 2:
          anchor = Offset(table.center.dx, table.top + 34);
          break;
        default:
          anchor = Offset(table.right - 30, table.center.dy);
      }

      for (var i = 0; i < n; i++) {
        final t = i - (n - 1) / 2;
        final Offset slot;
        if (side == 0) {
          slot = Offset(
            (rack?.center.dx ?? table.center.dx) + t * step,
            rack?.center.dy ?? table.bottom - 14,
          );
        } else if (side == 2) {
          slot = Offset(
            table.left + 10 + across / 2 + i * step,
            table.top + 26,
          );
        } else if (side == 1) {
          slot = Offset(table.left + 18, table.center.dy + t * step);
        } else {
          slot = Offset(table.right - 18, table.center.dy + t * step);
        }
        specs.add(
          _RevealSpec(
            tile: tiles[i],
            hand: anchor,
            slot: slot,
            angle: row ? math.pi / 2 : 0,
            delay: i * 14.0,
          ),
        );
      }
    }

    if (specs.isEmpty) return null;

    final cols =
        math.min(7, math.max(1, math.sqrt(specs.length * 1.7).ceil()));
    final rows = (specs.length / cols).ceil();
    for (var i = 0; i < specs.length; i++) {
      specs[i].gather =
          table.center +
          Offset(
            (i % cols - (cols - 1) / 2) * 34,
            (i ~/ cols - (rows - 1) / 2) * 17,
          );
    }

    final controller = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 4600),
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
                for (var i = 0; i < specs.length; i++)
                  _buildTile(specs[i], i, ms, spriteW, spriteH),
              ],
            );
          },
        ),
      ),
    );
    Overlay.of(context).insert(entry);
    final run = HandRevealRun._(controller, entry);
    controller.forward(from: 0).whenCompleteOrCancel(run._finish);
    return run;
  }

  static int _identitySide(int seat) => seat;

  static Widget _buildTile(
    _RevealSpec s,
    int i,
    double ms,
    double w,
    double h,
  ) {
    var pos = s.slot;
    var angle = s.angle;
    var opacity = 1.0;

    final emerge = (ms - s.delay) / 260;
    if (emerge < 1) {
      final p = Curves.easeOutCubic.transform(emerge.clamp(0.0, 1.0));
      pos = Offset.lerp(s.hand, s.slot, p)!;
      opacity = p;
    }

    final gatherStart = 2960 + s.delay;
    if (ms >= gatherStart) {
      final p = Curves.easeInOutCubic.transform(
        ((ms - gatherStart) / 700).clamp(0.0, 1.0),
      );
      pos = Offset.lerp(s.slot, s.gather, p)!;
      angle = s.angle + (math.pi / 2 - s.angle) * p;
    }

    const shakeStart = 3300.0;
    const shakeEnd = 4060.0;
    if (ms >= shakeStart && ms <= shakeEnd) {
      final k = math.sin(
        math.pi * ((ms - shakeStart) / (shakeEnd - shakeStart)).clamp(0.0, 1.0),
      );
      pos += Offset(
        math.sin(ms / 34 + i * 1.9) * 4.0 * k,
        math.cos(ms / 27 + i * 2.4) * 2.5 * k,
      );
    }

    final returnStart = 4010 + s.delay;
    if (ms >= returnStart) {
      final p = Curves.easeInCubic.transform(
        ((ms - returnStart) / 470).clamp(0.0, 1.0),
      );
      pos = Offset.lerp(s.gather, s.hand, p)!;
      angle = math.pi / 2 + (s.angle - math.pi / 2) * p;
      opacity = 1 - p;
    }

    return Positioned(
      left: pos.dx - w / 2,
      top: pos.dy - h / 2,
      width: w,
      height: h,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform.rotate(
          angle: angle,
          child: Image.asset(
            _faceAsset(s.tile),
            width: w,
            height: h,
            fit: BoxFit.fill,
          ),
        ),
      ),
    );
  }

  static String _faceAsset(DominoTile t) {
    final hi = math.max(t.top, t.bottom);
    final lo = math.min(t.top, t.bottom);
    return 'assets/tiles/t1d$hi$lo.png';
  }
}

/// Handle to one running reveal. [dispose] stops it early and removes it.
class HandRevealRun {
  HandRevealRun._(this._controller, this._entry);

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

class _RevealSpec {
  final DominoTile tile;
  final Offset hand;
  final Offset slot;
  final double angle;
  final double delay;
  late Offset gather;

  _RevealSpec({
    required this.tile,
    required this.hand,
    required this.slot,
    required this.angle,
    required this.delay,
  });
}
