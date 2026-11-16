import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/domino_tile.dart';

/// Plays the end-of-hand shuffle: every tile on the table (the board plus the
/// four hands, 28 in total) flips face-down, gathers in the middle, shakes,
/// then flies out to the four hands.
///
/// Shared by practice and online. The caller owns the [TickerProvider] and
/// must [HandRevealRun.dispose] if it is torn down mid-animation.
class HandReveal {
  HandReveal._();

  static const int durationMs = 8000;

  /// Face-up hold, then the flip, the gather, the shake and the deal.
  static const double _holdUntilMs = 2900;
  static const double _flipMs = 280;
  static const double _gatherStartMs = 3150;
  static const double _gatherMs = 850;
  static const double _shakeStartMs = 3950;
  static const double _shakeEndMs = 6300;
  static const double _dealMs = 900;
  static const double _tileScale = 0.5;

  /// [hands] is indexed by seat. [boardTiles] are the tiles already on the
  /// table, with their screen centre and size. [sideOfHand] maps a seat to a
  /// table side: 0 = bottom (you), 1 = left, 2 = top, 3 = right.
  static HandRevealRun? play({
    required BuildContext context,
    required TickerProvider vsync,
    required Rect table,
    required Rect? rack,
    required List<List<DominoTile>> hands,
    List<
      ({
        DominoTile tile,
        Offset center,
        double scale,
        bool horizontal,
        bool flipped,
      })
    >
    boardTiles = const [],
    int Function(int seat) sideOfHand = _identitySide,
  }) {
    final specs = <_RevealSpec>[];
    var index = 0;

    // Tiles in the players' hands, waiting on their own side.
    for (var seat = 0; seat < hands.length; seat++) {
      final tiles = hands[seat];
      if (tiles.isEmpty) continue;
      final side = sideOfHand(seat) % 4;
      final n = tiles.length;
      final row = side == 0 || side == 2;
      final along = 60.0 * _tileScale;
      final perp = 130.0 * _tileScale;
      final room = row
          ? math.max(along, table.width - 28)
          : math.max(along, table.height * 0.68);
      final step = n > 1
          ? math.min(
              along + 2,
              math.max(along * 0.5, (room - along) / (n - 1)),
            )
          : along + 2;
      final angle = switch (side) {
        0 => 0.0,
        2 => math.pi,
        1 => math.pi / 2,
        _ => -math.pi / 2,
      };

      for (var i = 0; i < n; i++) {
        final t = i - (n - 1) / 2;
        final Offset slot;
        if (side == 0) {
          slot = Offset(
            (rack?.center.dx ?? table.center.dx) + t * step,
            rack?.center.dy ?? table.bottom - 14,
          );
        } else if (side == 2) {
          slot = Offset(table.center.dx + t * step, table.top + 4 + perp / 2);
        } else if (side == 1) {
          slot = Offset(table.left + 8 + perp / 2, table.center.dy + t * step);
        } else {
          slot = Offset(table.right - 8 - perp / 2, table.center.dy + t * step);
        }
        specs.add(
          _RevealSpec(
            tile: tiles[i],
            slot: slot,
            startScale: _tileScale,
            startAngle: angle,
            faceAngle: angle,
            delay: (index % 7) * 12.0,
          ),
        );
        index++;
      }
    }

    // Tiles already on the board. The caller hides the board while this runs,
    // so these backs take its place exactly.
    for (final tile in boardTiles) {
      final base = tile.horizontal ? math.pi / 2 : 0.0;
      specs.add(
        _RevealSpec(
          tile: tile.tile,
          slot: tile.center,
          startScale: tile.scale,
          startAngle: base,
          faceAngle: base + (tile.flipped ? math.pi : 0),
          delay: (index % 7) * 12.0,
        ),
      );
      index++;
    }

    if (specs.isEmpty) return null;

    final cols =
        math.min(7, math.max(1, math.sqrt(specs.length * 1.7).ceil()));
    final rows = (specs.length / cols).ceil();
    for (var i = 0; i < specs.length; i++) {
      specs[i].gather =
          table.center +
          Offset(
            (i % cols - (cols - 1) / 2) * 30,
            (i ~/ cols - (rows - 1) / 2) * 15,
          );
      final side = (i ~/ 7).clamp(0, 3);
      specs[i].dealAnchor = switch (side) {
        0 => rack?.center ?? Offset(table.center.dx, table.bottom - 14),
        1 => Offset(table.left + 30, table.center.dy),
        2 => Offset(table.center.dx, table.top + 34),
        _ => Offset(table.right - 30, table.center.dy),
      };
      specs[i].dealAngle = switch (side) {
        0 => 0.0,
        2 => math.pi,
        1 => math.pi / 2,
        _ => -math.pi / 2,
      };
    }

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
                for (var i = 0; i < specs.length; i++)
                  _buildTile(specs[i], i, ms),
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

  static Widget _buildTile(_RevealSpec s, int i, double ms) {
    var pos = s.slot;
    var scale = s.startScale;
    var angle = s.startAngle;
    var opacity = 1.0;

    final appear = (ms - s.delay) / 300;
    if (appear < 1) opacity = appear.clamp(0.0, 1.0);

    // Everyone sees the faces first, then the tiles flip face-down.
    final flip = ((ms - (_holdUntilMs + s.delay)) / _flipMs).clamp(0.0, 1.0);
    final showBack = flip >= 0.5;
    final flipX = math.cos(math.pi * flip).abs();

    final gatherStart = _gatherStartMs + s.delay;
    if (ms >= gatherStart) {
      final p = Curves.easeInOutCubic.transform(
        ((ms - gatherStart) / _gatherMs).clamp(0.0, 1.0),
      );
      pos = Offset.lerp(s.slot, s.gather, p)!;
      scale = s.startScale + (_tileScale - s.startScale) * p;
      angle = _lerpAngle(s.startAngle, math.pi / 2, p);
    }

    if (ms >= _shakeStartMs && ms <= _shakeEndMs) {
      final k = math.sin(
        math.pi *
            ((ms - _shakeStartMs) / (_shakeEndMs - _shakeStartMs)).clamp(
              0.0,
              1.0,
            ),
      );
      pos += Offset(
        math.sin(ms / 34 + i * 1.9) * 4.0 * k,
        math.cos(ms / 27 + i * 2.4) * 2.5 * k,
      );
    }

    final dealStart = _shakeEndMs + s.delay;
    if (ms >= dealStart) {
      final p = Curves.easeInOutCubic.transform(
        ((ms - dealStart) / _dealMs).clamp(0.0, 1.0),
      );
      pos = Offset.lerp(s.gather, s.dealAnchor, p)!;
      angle = _lerpAngle(math.pi / 2, s.dealAngle, p);
      opacity = 1 - p;
    }

    final w = 60.0 * scale;
    final h = 130.0 * scale;
    final asset = showBack ? 'assets/tiles/t1back.png' : _faceAsset(s.tile);
    return Positioned(
      left: pos.dx - w / 2,
      top: pos.dy - h / 2,
      width: w,
      height: h,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform.rotate(
          angle: showBack ? angle : s.faceAngle,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()..scale(flipX, 1.0),
            child: Image.asset(
              asset,
              width: w,
              height: h,
              fit: BoxFit.fill,
            ),
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
  final Offset slot;
  final double startScale;
  final double startAngle;
  final double faceAngle;
  final double delay;
  late Offset gather;
  late Offset dealAnchor;
  late double dealAngle;

  _RevealSpec({
    required this.tile,
    required this.slot,
    required this.startScale,
    required this.startAngle,
    required this.faceAngle,
    required this.delay,
  });
}

/// Rotates from [a] to [b] the short way round.
double _lerpAngle(double a, double b, double t) {
  var delta = b - a;
  while (delta > math.pi) {
    delta -= 2 * math.pi;
  }
  while (delta < -math.pi) {
    delta += 2 * math.pi;
  }
  return a + delta * t;
}
