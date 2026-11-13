import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';

import 'package:domino/models/domino_tile.dart';
import 'package:domino/models/game_state.dart';
import 'package:domino/widgets/game_board.dart';

/// Chain order (play order): center first, then right/left tiles.
final _board = [
  PlacedTile(const DominoTile(6, 6), 'right', 6),
  PlacedTile(const DominoTile(6, 3), 'right', 6),
  PlacedTile(const DominoTile(3, 4), 'right', 3),
  PlacedTile(const DominoTile(4, 4), 'right', 4),
  PlacedTile(const DominoTile(4, 5), 'right', 4),
  PlacedTile(const DominoTile(5, 1), 'right', 5),
  PlacedTile(const DominoTile(2, 6), 'left', 6),
  PlacedTile(const DominoTile(1, 2), 'left', 2),
  PlacedTile(const DominoTile(0, 1), 'left', 1),
];

bool _sharesSuit(DominoTile a, DominoTile b) =>
    a.minor == b.minor ||
    a.minor == b.major ||
    a.major == b.minor ||
    a.major == b.major;

void main() {
  test('buildChain groups tiles into left/right chains from center', () {
    final chain = buildChain(_board);

    expect(chain.center, const DominoTile(6, 6));
    expect(chain.right.length, 5);
    expect(chain.left.length, 3);
    expect(chain.up, isEmpty);
    expect(chain.down, isEmpty);

    // Center connects to the first tile of each chain.
    expect(
      _sharesSuit(chain.center, chain.right.first),
      isTrue,
      reason: 'center must connect to first right tile',
    );
    expect(
      _sharesSuit(chain.center, chain.left.first),
      isTrue,
      reason: 'center must connect to first left tile',
    );

    // Every consecutive pair in each chain shares a suit.
    for (var i = 0; i < chain.right.length - 1; i++) {
      expect(
        _sharesSuit(chain.right[i], chain.right[i + 1]),
        isTrue,
        reason: 'right chain joint at $i',
      );
    }
    for (var i = 0; i < chain.left.length - 1; i++) {
      expect(
        _sharesSuit(chain.left[i], chain.left[i + 1]),
        isTrue,
        reason: 'left chain joint at $i',
      );
    }
  });

  test('computeLayout has no overlapping tiles and fits bounds', () {
    for (final w in [200.0, 320.0, 400.0, 700.0, 900.0]) {
      for (final h in [200.0, 300.0, 500.0]) {
        final layout = computeLayout(_board, maxWidth: w, maxHeight: h);

        expect(
          layout.positions.length,
          9,
          reason: 'all 9 tiles placed at $w x $h',
        );

        expect(layout.bounds.width.isFinite, isTrue);
        expect(layout.bounds.height.isFinite, isTrue);
        expect(layout.bounds.width, greaterThan(0));
        expect(layout.bounds.height, greaterThan(0));

        // Should be reasonably close to the play area.
        expect(
          layout.bounds.width,
          lessThanOrEqualTo(w * 1.1),
          reason: 'too wide at $w x $h',
        );
        expect(
          layout.bounds.height,
          lessThanOrEqualTo(h * 1.1),
          reason: 'too tall at $w x $h',
        );

        // No two tiles overlap.
        final rects = _placementRects(layout);
        for (var i = 0; i < rects.length; i++) {
          for (var j = i + 1; j < rects.length; j++) {
            final inter = rects[i].intersect(rects[j]);
            final area = inter.isEmpty ? 0.0 : inter.width * inter.height;
            expect(
              area,
              lessThan(0.001),
              reason: 'tiles $i and $j overlap at $w x $h',
            );
          }
        }
      }
    }
  });

  test('root tile is centered and no tile is duplicated', () {
    for (final w in [320.0, 400.0, 700.0]) {
      for (final h in [300.0, 500.0]) {
        final layout = computeLayout(_board, maxWidth: w, maxHeight: h);

        final seen = <String>{};
        for (final pos in layout.positions) {
          expect(
            seen.add(pos.tile.toString()),
            isTrue,
            reason: 'duplicate tile ${pos.tile} at $w x $h',
          );
        }
        expect(layout.positions.length, 9);

        // The root tile sits at the layout origin (na places it at 0,0).
        final rootPlacement = layout.positions.firstWhere(
          (pos) => pos.tile == const DominoTile(6, 6),
        );
        expect(
          rootPlacement.offset.dx.abs(),
          lessThan(0.001),
          reason: 'root not centered horizontally at $w x $h',
        );
        expect(
          rootPlacement.offset.dy.abs(),
          lessThan(0.001),
          reason: 'root not centered vertically at $w x $h',
        );
      }
    }
  });

  test('center-only board produces a single centered tile', () {
    final board = [PlacedTile(const DominoTile(6, 6), 'right', 6)];
    final layout = computeLayout(board, maxWidth: 300, maxHeight: 300);
    expect(layout.positions.length, 1);
    expect(layout.positions.first.tile, const DominoTile(6, 6));
    expect(layout.positions.first.offset.dx.abs(), lessThan(0.001));
    expect(layout.positions.first.offset.dy.abs(), lessThan(0.001));
  });

  test('crosswise doubles count as half a segment tile', () {
    final board = [
      PlacedTile(const DominoTile(6, 6), 'center', 6),
      for (var i = 0; i < 11; i++)
        PlacedTile(const DominoTile(0, 0), 'left', 0),
    ];
    final layout = computeLayout(board, maxWidth: 1600, maxHeight: 1600);
    final leftTiles = layout.positions.skip(1).toList();

    // The initial short segment ends after two doubles; the next full segment
    // should still be heading up at tile 7, not turn right as if doubles were
    // full-length tiles.
    expect(leftTiles[6].offset.dy, lessThan(leftTiles[5].offset.dy));
    expect(leftTiles[10].offset.dx, greaterThan(leftTiles[9].offset.dx));
  });

  test('played doubles cross the chain direction', () {
    final board = [
      PlacedTile(const DominoTile(6, 6), 'center', 6),
      PlacedTile(const DominoTile(6, 2), 'left', 6),
      PlacedTile(const DominoTile(2, 2), 'left', 2),
    ];
    final layout = computeLayout(board, maxWidth: 500, maxHeight: 500);
    final doublePlacement = layout.positions.firstWhere(
      (pos) => pos.tile == const DominoTile(2, 2),
    );

    expect(doublePlacement.horizontal, isFalse);
  });

  test('double at a turn slides only a quarter edge toward the prior run', () {
    final board = [
      PlacedTile(const DominoTile(6, 6), 'center', 6),
      PlacedTile(const DominoTile(6, 2), 'left', 6),
      PlacedTile(const DominoTile(2, 3), 'left', 2),
      PlacedTile(const DominoTile(3, 3), 'left', 3),
      PlacedTile(const DominoTile(3, 4), 'left', 3),
    ];
    final layout = computeLayout(board, maxWidth: 1000, maxHeight: 1000);
    final prior = layout.positions.firstWhere(
      (pos) => pos.tile == const DominoTile(2, 3),
    );
    final doublePlacement = layout.positions.firstWhere(
      (pos) => pos.tile == const DominoTile(3, 3),
    );
    final following = layout.positions.firstWhere(
      (pos) => pos.tile == const DominoTile(3, 4),
    );

    expect(
      doublePlacement.offset.dx,
      closeTo(prior.offset.dx - 130 * layout.scale / 4, 0.001),
    );
    expect(following.offset.dx, closeTo(doublePlacement.offset.dx, 0.001));
  });

  test('buildChain keeps 4-direction support for top/bottom sides', () {
    final board = [
      PlacedTile(const DominoTile(6, 6), 'right', 6),
      PlacedTile(const DominoTile(6, 3), 'right', 6),
      PlacedTile(const DominoTile(6, 2), 'left', 6),
      PlacedTile(const DominoTile(6, 5), 'top', 6),
      PlacedTile(const DominoTile(6, 4), 'bottom', 6),
    ];
    final chain = buildChain(board);
    expect(chain.right.single, const DominoTile(6, 3));
    expect(chain.left.single, const DominoTile(6, 2));
    expect(chain.up.single, const DominoTile(6, 5));
    expect(chain.down.single, const DominoTile(6, 4));

    final layout = computeLayout(board, maxWidth: 400, maxHeight: 400);
    expect(layout.positions.length, 5);
    final seen = <String>{};
    for (final pos in layout.positions) {
      expect(seen.add(pos.tile.toString()), isTrue);
    }
  });
}

List<Rect> _placementRects(SnakeLayout layout) {
  return layout.positions.map((pos) {
    final w = pos.horizontal ? 102.0 : 50.0;
    final h = pos.horizontal ? 50.0 : 102.0;
    final rect = Rect.fromLTWH(
      pos.offset.dx - layout.bounds.left - w * layout.scale / 2,
      pos.offset.dy - layout.bounds.top - h * layout.scale / 2,
      w * layout.scale,
      h * layout.scale,
    );
    return rect;
  }).toList();
}
