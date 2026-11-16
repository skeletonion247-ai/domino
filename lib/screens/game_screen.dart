import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/domino_set.dart';
import '../models/domino_tile.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../services/audio_service.dart';
import '../services/practice_session.dart';
import '../widgets/brick_throw.dart';
import '../widgets/emote_burst.dart';
import '../widgets/emote_picker.dart';
import '../widgets/game_board.dart';
import '../widgets/hand_over_dialog.dart';
import '../widgets/hand_reveal.dart';
import '../widgets/leave_game_dialog.dart';
import '../widgets/opponent_seat.dart';
import '../widgets/player_rack.dart';
import '../widgets/score_fly.dart';
import '../widgets/score_header.dart';
import '../widgets/sprite_domino_tile.dart';

/// Playable game table (Block, 2v2). The bots pick the first matching tile so
/// we can test the flow while the full rules are wired.
class GameScreen extends StatefulWidget {
  final bool autoPlay;

  const GameScreen({super.key, this.autoPlay = true});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with TickerProviderStateMixin {
  static const int _targetScore = 100;
  static const double _turnSeconds = 20;

  final GlobalKey _boardKey = GlobalKey();
  final GlobalKey _team1Key = GlobalKey();
  final GlobalKey _team2Key = GlobalKey();
  ScoreFlyRun? _scoreFlyRun;
  BrickThrowRun? _brickRun;
  EmoteBurstRun? _emoteBurst;
  final GlobalKey _rackAvatarKey = GlobalKey();
  final GlobalKey _topAvatarKey = GlobalKey();
  int _pendingScoreTeam = -1;
  int _pendingScorePoints = 0;
  final GlobalKey _rackKey = GlobalKey();
  final GlobalKey _tableKey = GlobalKey();
  late final AnimationController _flyController;
  final ValueNotifier<double> _turnProgress = ValueNotifier<double>(1);
  OverlayEntry? _flyEntry;
  HandRevealRun? _revealRun;
  bool _revealing = false;
  bool _animating = false;
  final List<GlobalKey> _seatKeys = List.generate(4, (_) => GlobalKey());
  DominoTile? _selected;
  Rect? _selectedFromRect;
  DominoTile? _dragTile;

  int _team1Score = 45;
  int _team2Score = 34;
  int _current = 0;
  Timer? _botTimer;
  Timer? _ticker;
  DateTime _turnStart = DateTime.now();
  int _turnIndex = -1;
  int _consecutivePasses = 0;
  bool _handOver = false;
  bool _quitting = false;

  late final List<DominoTile> _hand;

  /// Vertical run length for each line of the practice snake. Both start at
  /// the classic 3 and may each grow to 4 once, if that line has free space.
  /// They never change back mid-hand.
  double _topRun = 3;
  double _bottomRun = 3;

  late final List<PlacedTile> _board;

  late final List<Player> _players;

  @override
  void initState() {
    super.initState();
    _flyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );

    final saved = PracticeSession.instance;
    if (saved.active) {
      _hand = saved.hand;
      _players = saved.players;
      _board = saved.board;
      _team1Score = saved.team1Score;
      _team2Score = saved.team2Score;
      _current = saved.current;
      _consecutivePasses = saved.consecutivePasses;
      _handOver = saved.handOver;
      _topRun = saved.topRun;
      _bottomRun = saved.bottomRun;
      if (_handOver) {
        if (_team1Score >= _targetScore || _team2Score >= _targetScore) {
          _dealGame();
        } else {
          _dealHand();
        }
      }
    } else {
      _hand = <DominoTile>[];
      _players = [
        Player(name: 'You', team: 0),
        Player(name: 'Bot 1', team: 1),
        Player(name: 'Bot 2', team: 0),
        Player(name: 'Bot 3', team: 1),
      ];
      _board = <PlacedTile>[];
      saved.bind(hand: _hand, players: _players, board: _board);
      _dealGame();
    }

    _ticker = Timer.periodic(const Duration(milliseconds: 100), _onTick);
    _scheduleBots();
    WidgetsBinding.instance.addPostFrameCallback((_) => _precacheTiles());
  }

  /// Decode every tile sprite up front so no tile can show up blank mid-game
  /// while its image is still loading.
  Future<void> _precacheTiles() async {
    final assets = <String>[
      'assets/tiles/t1back.png',
      'assets/tiles/t1shadow.png',
      for (var hi = 0; hi <= 6; hi++)
        for (var lo = 0; lo <= hi; lo++) 'assets/tiles/t1d$hi$lo.png',
    ];
    for (final asset in assets) {
      if (!mounted) return;
      await precacheImage(AssetImage(asset), context, onError: (_, _) {});
    }
  }

  @override
  void dispose() {
    _botTimer?.cancel();
    _ticker?.cancel();
    final session = PracticeSession.instance;
    if (_quitting) {
      session.clear();
    } else {
      session
        ..active = true
        ..team1Score = _team1Score
        ..team2Score = _team2Score
        ..current = _current
        ..consecutivePasses = _consecutivePasses
        ..handOver = _handOver
        ..topRun = _topRun
        ..bottomRun = _bottomRun;
    }
    _turnProgress.dispose();
    _flyEntry?.remove();
    _flyEntry = null;
    _revealRun?.dispose();
    _revealRun = null;
    // The chips may still be flying: land the points before saving.
    if (_pendingScoreTeam >= 0) {
      if (_pendingScoreTeam == 0) {
        _team1Score += _pendingScorePoints;
      } else {
        _team2Score += _pendingScorePoints;
      }
      _pendingScoreTeam = -1;
      _pendingScorePoints = 0;
    }
    _scoreFlyRun?.dispose();
    _scoreFlyRun = null;
    _brickRun?.dispose();
    _brickRun = null;
    _emoteBurst?.dispose();
    _emoteBurst = null;
    _flyController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Item B — turn timer
  // ---------------------------------------------------------------------------

  void _onTick(Timer timer) {
    if (!mounted) return;
    if (_current != _turnIndex) {
      _turnIndex = _current;
      _turnStart = DateTime.now();
    }
    if (_handOver || _animating) return;
    _turnProgress.value = _turnFraction;
    if (_turnFraction <= 0) {
      _onTurnTimeout();
      return;
    }
  }

  double get _turnFraction {
    final elapsed =
        DateTime.now().difference(_turnStart).inMilliseconds / 1000.0;
    return ((_turnSeconds - elapsed).clamp(0.0, _turnSeconds) / _turnSeconds);
  }

  void _onTurnTimeout() {
    if (_handOver || _animating) return;
    _turnStart = DateTime.now();

    if (_current == 0) {
      final moves = _hand.where((t) {
        final (l, r) = _openEnds();
        return t.matches(l) || t.matches(r);
      }).toList();
      if (moves.isEmpty) {
        _registerPass();
      } else {
        final tile = moves.first;
        final (l, r) = _openEnds();
        final side = tile.matches(l) ? 'left' : 'right';
        _commitPlay(tile, side, side == 'left' ? l : r);
      }
    } else {
      _botTimer?.cancel();
      _playBot();
    }
  }

  /// Item A — real match setup: shuffle the 28 tiles, deal 7 to each player
  /// (no boneyard), then the 6-6 owner plays it automatically.
  /// Item A — a fresh match: reset the score, then deal the first hand.
  void _dealGame() {
    _team1Score = 0;
    _team2Score = 0;
    _dealHand();
  }

  /// Deals one hand: shuffle 28, 7 each (no boneyard), 6-6 owner auto-plays.
  void _dealHand() {
    final tiles = createDoubleSixSet();
    shuffleTiles(tiles);

    _hand.clear();
    for (final player in _players) {
      player.hand.clear();
    }

    for (var i = 0; i < 7; i++) {
      _hand.add(tiles.removeAt(0));
      _players[1].hand.add(tiles.removeAt(0));
      _players[2].hand.add(tiles.removeAt(0));
      _players[3].hand.add(tiles.removeAt(0));
    }

    _board.clear();
    _consecutivePasses = 0;
    _handOver = false;
    _selected = null;
    _dragTile = null;
    _animating = false;

    final hands = [_hand, _players[1].hand, _players[2].hand, _players[3].hand];
    for (var i = 0; i < hands.length; i++) {
      final index = hands[i].indexWhere(
        (tile) => tile.isDouble && tile.top == 6,
      );
      if (index >= 0) {
        final sixSix = hands[i].removeAt(index);
        _board.add(PlacedTile(sixSix, 'center', 6));
        _current = (i + 1) % 4;
        break;
      }
    }

    _topRun = 3;
    _bottomRun = 3;
    _turnStart = DateTime.now();
    _turnIndex = -1;
    _turnProgress.value = 1;
  }

  /// Starts the next hand of the same match, keeping the scores.
  void _startNextHand() {
    _dealHand();
    setState(() {});
    _scheduleBots();
  }

  /// After the snake has grown, let each line take one extra vertical tile
  /// when that line still has free space above/below. "Free space" means the
  /// extra tile fits without shrinking the tiles or overlapping anything.
  /// Top and bottom are decided independently and each switch is one-way, so
  /// the snake cannot keep reshaping move after move.
  void _maybeGrowVerticalRuns() {
    if (_topRun == 4 && _bottomRun == 4) return;
    final box = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final next = growVerticalRuns(
      board: _board,
      size: box.size,
      top: _topRun,
      bottom: _bottomRun,
    );
    if (next.top != _topRun || next.bottom != _bottomRun) {
      setState(() {
        _topRun = next.top;
        _bottomRun = next.bottom;
      });
    }
  }

  (int, int) _openEnds() {
    final center = _board.first.tile;
    var left = center.top;
    var right = center.bottom;
    for (var i = 1; i < _board.length; i++) {
      final p = _board[i];
      if (p.side == 'left') {
        left = p.tile.getOtherEnd(p.connectedEnd);
      } else {
        right = p.tile.getOtherEnd(p.connectedEnd);
      }
    }
    return (left, right);
  }

  Set<DominoTile> get _playable {
    if (_handOver || _animating || _current != 0) return {};
    final (left, right) = _openEnds();
    return _hand.where((t) => t.matches(left) || t.matches(right)).toSet();
  }

  ({bool left, bool right}) _endsFor(DominoTile tile) {
    final (left, right) = _openEnds();
    return (left: tile.matches(left), right: tile.matches(right));
  }

  void _playHuman(DominoTile tile, Rect? fromRect) {
    if (_handOver || _animating || _current != 0) return;
    if (_selected == tile) {
      setState(() => _selected = null);
      return;
    }
    final ends = _endsFor(tile);
    if (!ends.left && !ends.right) return;
    // Select the tile; the player then taps the end where it should go.
    AudioService.instance.playClick();
    setState(() {
      _selected = tile;
      _selectedFromRect = fromRect;
    });
  }

  void _chooseEnd(String side) {
    final tile = _selected;
    if (tile == null) return;
    final from = _selectedFromRect;
    setState(() => _selected = null);
    AudioService.instance.playClick();
    _startPlay(tile, side, from);
  }

  void _onDropTile(DominoTile tile, String side, Offset dropPoint) {
    if (_handOver || _animating || _current != 0) return;
    final ends = _endsFor(tile);
    if (side == 'left' ? !ends.left : !ends.right) return;
    setState(() => _selected = null);
    _startPlay(tile, side, Rect.fromLTWH(dropPoint.dx, dropPoint.dy, 40, 88));
  }

  void _startPlay(DominoTile tile, String side, Rect? fromRect) {
    if (_handOver || _animating || _current != 0) return;
    final (left, right) = _openEnds();
    final connected = side == 'left' ? left : right;

    final target = _boardTargetRect(tile, side, connected);
    if (fromRect == null || target == null) {
      _commitPlay(tile, side, connected);
      return;
    }

    setState(() {
      _hand.remove(tile);
      _animating = true;
      _selected = null;
    });
    _flyTile(tile, fromRect, target, () {
      _commitPlay(tile, side, connected);
    });
  }

  void _commitPlay(DominoTile tile, String side, int connected) {
    setState(() {
      _hand.remove(tile);
      _board.add(PlacedTile(tile, side, connected));
      _current = 1;
      _consecutivePasses = 0;
      _animating = false;
      _selected = null;
      _dragTile = null;
    });
    _maybeGrowVerticalRuns();
    if (_hand.isEmpty) {
      _endHand(0);
      return;
    }
    _scheduleBots();
  }

  /// Where [tile] will land after playing it on [side]. Global by default,
  /// or board-widget-local when [local] is true.
  ({Rect rect, bool horizontal, bool flipped})? _placementFor(
    DominoTile tile,
    String side,
    int connected, {
    required bool local,
  }) {
    final ctx = _boardKey.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final size = box.size;
    final origin = local ? Offset.zero : box.localToGlobal(Offset.zero);

    final sim = [..._board, PlacedTile(tile, side, connected)];
    final layout = computeLayout(
      sim,
      maxWidth: size.width,
      maxHeight: size.height,
      smart: true,
      topRun: _topRun,
      bottomRun: _bottomRun,
    );
    final bounds = layout.bounds;
    final scale = layout.scale;

    var placement = layout.positions.first;
    for (final p in layout.positions) {
      if (p.tile.top == tile.top && p.tile.bottom == tile.bottom) {
        placement = p;
        break;
      }
    }

    final anchor = boardOrigin(size, bounds);
    final w = (placement.horizontal ? 130.0 : 60.0) * scale;
    final h = (placement.horizontal ? 60.0 : 130.0) * scale;

    final rect = Rect.fromLTWH(
      origin.dx + anchor.dx + placement.offset.dx - w / 2,
      origin.dy + anchor.dy + placement.offset.dy - h / 2,
      w,
      h,
    );
    return (
      rect: rect,
      horizontal: placement.horizontal,
      flipped: placement.isFlipped,
    );
  }

  ({Rect rect, bool horizontal, bool flipped})? _boardTargetRect(
    DominoTile tile,
    String side,
    int connected,
  ) => _placementFor(tile, side, connected, local: false);

  void _flyTile(
    DominoTile tile,
    Rect from,
    ({Rect rect, bool horizontal, bool flipped}) target,
    VoidCallback onDone, {
    bool fromHorizontal = false,
  }) {
    final overlay = Overlay.of(context);
    final face = _faceAsset(tile);
    final horizontal = target.horizontal;
    final flipped = target.flipped;
    final to = target.rect;
    final fromScale = (from.height / (fromHorizontal ? 60 : 130))
        .clamp(0.2, 1.0)
        .toDouble();
    final toScale = ((to.height / (horizontal ? 60 : 130)) * 0.98)
        .clamp(0.2, 1.0)
        .toDouble();
    final targetTurns = (horizontal ? 1 : 0) + (flipped ? 2 : 0);
    var targetAngle = targetTurns * math.pi / 2;
    if (targetAngle > math.pi) targetAngle -= math.pi * 2;
    final startAngle = fromHorizontal ? math.pi / 2 : 0.0;
    var angleDelta = targetAngle - startAngle;
    if (angleDelta > math.pi) angleDelta -= math.pi * 2;
    if (angleDelta < -math.pi) angleDelta += math.pi * 2;

    _flyEntry?.remove();
    _flyEntry = OverlayEntry(
      builder: (_) => IgnorePointer(
        child: AnimatedBuilder(
          animation: _flyController,
          builder: (context, _) {
            final t = Curves.easeInOutCubic.transform(_flyController.value);
            final center =
                Offset.lerp(from.center, to.center, t)! +
                Offset(0, -42 * math.sin(math.pi * t));
            final scale = fromScale + (toScale - fromScale) * t;
            final angle = startAngle + angleDelta * t;
            final imageWidth = 60 * scale;
            final imageHeight = 130 * scale;
            return Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  left: center.dx - imageWidth / 2,
                  top: center.dy - imageHeight / 2,
                  width: imageWidth,
                  height: imageHeight,
                  child: Transform.rotate(
                    angle: angle,
                    child: Image.asset(
                      face,
                      width: imageWidth,
                      height: imageHeight,
                      fit: BoxFit.fill,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
    overlay.insert(_flyEntry!);
    _flyController.forward(from: 0).whenCompleteOrCancel(() {
      if (_flyEntry != null) {
        _flyEntry!.remove();
        _flyEntry = null;
      }
      if (!mounted) return;
      onDone();
    });
  }

  String _faceAsset(DominoTile t) {
    final hi = t.top > t.bottom ? t.top : t.bottom;
    final lo = t.top > t.bottom ? t.bottom : t.top;
    return 'assets/tiles/t1d$hi$lo.png';
  }

  DominoTile get _leftEndTile {
    var t = _board.first.tile;
    for (final p in _board) {
      if (p.side == 'left') t = p.tile;
    }
    return t;
  }

  DominoTile get _rightEndTile {
    var t = _board.first.tile;
    for (final p in _board) {
      if (p.side == 'right') t = p.tile;
    }
    return t;
  }

  /// Preview slot (board-local) adjacent to the *current* end tile, so the
  /// marker lines up with the board as it is drawn right now.
  Rect? _previewRectFor(DominoTile tile, String side) {
    final ctx = _boardKey.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final size = box.size;

    final (left, right) = _openEnds();
    final connected = side == 'left' ? left : right;
    final sim = [..._board, PlacedTile(tile, side, connected)];

    final cur = computeLayout(
      _board,
      maxWidth: size.width,
      maxHeight: size.height,
      smart: true,
      topRun: _topRun,
      bottomRun: _bottomRun,
    );
    final next = computeLayout(
      sim,
      maxWidth: size.width,
      maxHeight: size.height,
      smart: true,
      topRun: _topRun,
      bottomRun: _bottomRun,
    );

    final endTile = side == 'left' ? _leftEndTile : _rightEndTile;
    TilePlacement? curEnd;
    for (final p in cur.positions) {
      if (p.tile.top == endTile.top && p.tile.bottom == endTile.bottom) {
        curEnd = p;
        break;
      }
    }
    TilePlacement? nextEnd;
    TilePlacement? nextNew;
    for (final p in next.positions) {
      if (p.tile.top == endTile.top && p.tile.bottom == endTile.bottom) {
        nextEnd = p;
      }
      if (p.tile.top == tile.top && p.tile.bottom == tile.bottom) {
        nextNew = p;
      }
    }
    if (curEnd == null || nextEnd == null || nextNew == null) return null;

    final ratio = cur.scale / next.scale;
    final delta = (nextNew.offset - nextEnd.offset) * ratio;
    final center = curEnd.offset + delta;

    final anchor = boardOrigin(size, cur.bounds);
    final localCenter = Offset(
      anchor.dx + center.dx,
      anchor.dy + center.dy,
    );

    final horizontal = nextNew.horizontal;
    final w = (horizontal ? 130.0 : 60.0) * cur.scale;
    final h = (horizontal ? 60.0 : 130.0) * cur.scale;
    return Rect.fromCenter(center: localCenter, width: w, height: h);
  }

  /// The destination slots (board-local) for [tile] on each valid side.
  ({Rect? left, Rect? right}) _placementRectsFor(DominoTile tile) {
    final (l, r) = _openEnds();
    final leftRect = tile.matches(l) ? _previewRectFor(tile, 'left') : null;
    final rightRect = tile.matches(r) ? _previewRectFor(tile, 'right') : null;
    return (left: leftRect, right: rightRect);
  }

  List<Widget> _buildEndTargets() {
    final tile = _dragTile ?? _selected;
    if (tile == null) return const [];
    if (_current != 0 || _handOver || _animating) return const [];

    final rects = _placementRectsFor(tile);
    return [
      if (rects.left != null) _endTarget('left', rects.left!),
      if (rects.right != null) _endTarget('right', rects.right!),
    ];
  }

  /// Converts a board-local rect to the table layer, where the targets live
  /// so the part hanging over the board edge stays clickable.
  Rect _tableRect(Rect rect) {
    final board = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    final table = _tableKey.currentContext?.findRenderObject() as RenderBox?;
    if (board == null || table == null) return rect;
    final delta =
        board.localToGlobal(Offset.zero) - table.localToGlobal(Offset.zero);
    return rect.shift(delta);
  }

  Widget _endTarget(String side, Rect boardRect) {
    final rect = _tableRect(boardRect);
    const touch = 16.0; // bigger tap area, the marker itself stays in the slot
    const inset = 4.0; // keeps the border off the neighbouring tiles
    return Positioned.fromRect(
      rect: rect.inflate(touch),
      child: DragTarget<DominoTile>(
        onWillAcceptWithDetails: (details) {
          final ends = _endsFor(details.data);
          return side == 'left' ? ends.left : ends.right;
        },
        onAcceptWithDetails: (details) =>
            _onDropTile(details.data, side, details.offset),
        builder: (context, candidate, rejected) {
          final hover = candidate.isNotEmpty;
          return GestureDetector(
            onTap: () => _chooseEnd(side),
            child: Padding(
              padding: const EdgeInsets.all(touch),
              child: Padding(
                padding: const EdgeInsets.all(inset),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  decoration: BoxDecoration(
                    color: hover
                        ? const Color(0xFFFFD700).withValues(alpha: 0.35)
                        : const Color(0xFF0A2518).withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.85),
                      width: 1.6,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFD700).withValues(
                          alpha: hover ? 0.35 : 0.18,
                        ),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Icon(
                      Icons.add_rounded,
                      color: const Color(0xFFFFD700),
                      size: (rect.shortestSide * 0.45).clamp(14.0, 24.0),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Offset? _centreOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  Future<void> _openEmotes() async {
    final origin = _centreOf(_rackAvatarKey) ?? _rectOf(_rackKey)?.center;
    if (origin == null) return;
    final choice = await showEmoteWheel(context, origin: origin);
    if (!mounted || choice == null) return;
    if (choice == 'brick') {
      _throwBrick();
    } else {
      final text = choice == 'laugh' ? 'HA HA HA' : 'GG WP';
      _emoteBurst?.dispose();
      _emoteBurst = EmoteBurst.play(
        context: context,
        vsync: this,
        at: origin,
        text: text,
      );
    }
  }

  void _throwBrick() {
    final rack = _rectOf(_rackKey);
    final table = _rectOf(_tableKey);
    if (rack == null || table == null) return;
    final from =
        _centreOf(_rackAvatarKey) ?? Offset(rack.left + 28, rack.top + 26);
    final to =
        _centreOf(_topAvatarKey) ??
        _seatRect(2)?.center ??
        Offset(table.center.dx, table.top + 70);
    _brickRun?.dispose();
    _brickRun = BrickThrow.play(
      context: context,
      vsync: this,
      from: from,
      to: to,
    );
  }

  Future<void> _confirmLeave() async {
    final action = await showLeaveGameDialog(context, online: false);
    if (!mounted || action == null || action == 'stay') return;
    if (action == 'quit') {
      _quitting = true;
      PracticeSession.instance.clear();
    }
    Navigator.of(context).maybePop();
  }

  void _reorderHand(int oldIndex, int newIndex) {
    // ReorderableListView already adjusts newIndex for the removed item.
    if (newIndex == oldIndex) return;
    setState(() {
      final tile = _hand.removeAt(oldIndex);
      _hand.insert(newIndex, tile);
    });
  }

  void _scheduleBots() {
    _botTimer?.cancel();
    if (_handOver) return;
    if (_current == 0) {
      if (widget.autoPlay) {
        if (_playable.isEmpty) {
          _botTimer = Timer(const Duration(milliseconds: 220), () {
            if (!mounted || _current != 0 || _playable.isNotEmpty) return;
            _registerPass();
          });
        } else {
          _botTimer = Timer(const Duration(milliseconds: 240), _playAutoHuman);
        }
        return;
      }
      // Human turn: auto-skip when there is nothing playable.
      if (_playable.isEmpty) {
        _botTimer = Timer(const Duration(milliseconds: 900), () {
          if (!mounted || _current != 0 || _playable.isNotEmpty) return;
          _registerPass();
        });
      }
      return;
    }
    _botTimer = Timer(
      Duration(milliseconds: widget.autoPlay ? 240 : 2500),
      _playBot,
    );
  }

  void _playAutoHuman() {
    if (!mounted || _handOver || _animating || _current != 0) return;
    final (left, right) = _openEnds();
    for (final tile in _hand) {
      final side = tile.matches(left)
          ? 'left'
          : tile.matches(right)
          ? 'right'
          : null;
      if (side == null) continue;
      _startPlay(tile, side, _rackTileRect(tile));
      return;
    }
    _registerPass();
  }

  Rect? _rackTileRect(DominoTile tile) {
    final box = _rackKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || _hand.isEmpty) return null;

    final count = _hand.length;
    final availableWidth = math.max(1.0, box.size.width - 84);
    final scale = ((availableWidth / count - 4) / 60)
        .clamp(0.25, 0.8)
        .toDouble();
    final tileWidth = 60 * scale;
    final tileHeight = 130 * scale;
    final slotWidth = tileWidth + 4;
    final totalWidth = count * slotWidth - 4;
    final leftPad = (availableWidth - totalWidth) / 2;
    final index = _hand.indexOf(tile).clamp(0, count - 1).toInt();
    final origin = box.localToGlobal(Offset.zero);
    return Rect.fromLTWH(
      origin.dx + 64 + leftPad + index * slotWidth - 1.4 * scale,
      origin.dy + 4 + (111 - tileHeight) / 2 - 2 * scale,
      tileWidth,
      tileHeight,
    );
  }

  void _playBot() {
    if (!mounted || _handOver || _current == 0) return;
    final player = _players[_current];
    final (left, right) = _openEnds();

    DominoTile? move;
    String? side;
    var connected = 0;
    for (final tile in player.hand) {
      if (tile.matches(left)) {
        move = tile;
        side = 'left';
        connected = left;
        break;
      }
      if (tile.matches(right)) {
        move = tile;
        side = 'right';
        connected = right;
        break;
      }
    }

    if (move != null && side != null) {
      _flyBotTile(_current, move, side, connected);
      return;
    }
    _registerPass();
  }

  /// Flies a bot's tile from its seat to the board so the table shows who
  /// played it, then places it and passes the turn.
  void _flyBotTile(int seat, DominoTile tile, String side, int connected) {
    final player = _players[seat];
    final seatBounds = _seatRect(seat);
    // Opponents' side tiles lie flat; the top opponent's tiles stand upright.
    final fromHorizontal = seat != 2;
    const sourceScale = 0.6048;
    final from = seatBounds == null
        ? null
        : Rect.fromCenter(
            center: seatBounds.center,
            width: (fromHorizontal ? 130 : 60) * sourceScale,
            height: (fromHorizontal ? 60 : 130) * sourceScale,
          );
    final target = _boardTargetRect(tile, side, connected);
    player.hand.remove(tile);

    void land() {
      if (!mounted) return;
      setState(() {
        _board.add(PlacedTile(tile, side, connected));
        _animating = false;
        _current = (seat + 1) % 4;
        _selected = null;
        _dragTile = null;
        _consecutivePasses = 0;
      });
      _maybeGrowVerticalRuns();
      if (player.hand.isEmpty) {
        _endHand(player.team);
        return;
      }
      _scheduleBots();
    }

    if (from == null || target == null) {
      land();
      return;
    }
    setState(() => _animating = true);
    _flyTile(tile, from, target, land, fromHorizontal: fromHorizontal);
  }

  Rect? _seatRect(int seat) {
    final box =
        _seatKeys[seat].currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// A player could not play. Count the pass; four in a row blocks the hand.
  void _registerPass() {
    _consecutivePasses++;
    if (_consecutivePasses >= 4) {
      _endBlocked();
      return;
    }
    setState(() {
      _current = (_current + 1) % 4;
      _selected = null;
      _dragTile = null;
    });
    _scheduleBots();
  }

  /// Blocked hand: the team with the fewest pips wins and scores the other
  /// team's pips.
  void _endBlocked() {
    final pips0 = _teamPips(0);
    final pips1 = _teamPips(1);
    final winningTeam = pips0 <= pips1 ? 0 : 1;
    final points = winningTeam == 0 ? pips1 : pips0;
    _finishHand(winningTeam, points);
  }

  void _endHand(int winningTeam) {
    final points = _teamPips(1 - winningTeam);
    _finishHand(winningTeam, points);
  }

  /// Adds the hand points, runs the tile reveal, then either ends the match
  /// (win card) or deals the next hand.
  void _finishHand(int winningTeam, int points) {
    _botTimer?.cancel();
    setState(() => _handOver = true);

    final projected =
        (winningTeam == 0 ? _team1Score : _team2Score) + points;
    final gameOver = projected >= _targetScore;
    // Chips fly to the winner's counter; the score lands when they arrive.
    _playScoreFly(winningTeam, points);
    _playReveal(() {
      if (!mounted) return;
      if (gameOver) {
        if (widget.autoPlay) {
          _botTimer = Timer(const Duration(milliseconds: 700), () {
            if (!mounted) return;
            _dealGame();
            setState(() {});
            _scheduleBots();
          });
          return;
        }
        _showHandOver(winningTeam, points);
        return;
      }
      _startNextHand();
    });
  }

  /// Foundation for the end-of-hand reveal.
  Rect? _rectOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Chips fly from the losing team's seats to the winner's score counter,
  /// then the points are added.
  void _playScoreFly(int winningTeam, int points) {
    final losing = 1 - winningTeam;
    final from = <Offset>[];
    for (var i = 0; i < _players.length; i++) {
      if (_players[i].team != losing) continue;
      final rect = _seatRect(i);
      if (rect != null) from.add(rect.center);
    }

    final key = winningTeam == 0 ? _team1Key : _team2Key;
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    final to = box != null && box.hasSize
        ? box.localToGlobal(box.size.center(Offset.zero))
        : const Offset(0, 48);

    void applyScore() {
      final team = _pendingScoreTeam;
      if (team < 0) return;
      final pts = _pendingScorePoints;
      _pendingScoreTeam = -1;
      _pendingScorePoints = 0;
      if (!mounted) return;
      setState(() {
        if (team == 0) {
          _team1Score += pts;
        } else {
          _team2Score += pts;
        }
      });
    }

    _pendingScoreTeam = winningTeam;
    _pendingScorePoints = points;

    _scoreFlyRun?.dispose();
    _scoreFlyRun = ScoreFly.play(
      context: context,
      vsync: this,
      from: from,
      to: to,
      points: points,
    );
    if (_scoreFlyRun == null) {
      applyScore();
      return;
    }
    _scoreFlyRun!.done.whenComplete(() {
      _scoreFlyRun = null;
      applyScore();
    });
  }

  /// End-of-hand reveal: every player's leftover tiles appear face-up on their
  /// own side of the table, gather and shake in the middle, then fly back.
  /// Screen centres of the tiles already on the board, used by the reveal to
  /// sweep all 28 tiles into the middle.
  List<
    ({
      DominoTile tile,
      Offset center,
      double scale,
      bool horizontal,
      bool flipped,
    })
  >
  _boardTileSpecs() {
    final box = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return const [];
    final size = box.size;
    final layout = computeLayout(
      _board,
      maxWidth: size.width,
      maxHeight: size.height,
      smart: true,
      topRun: _topRun,
      bottomRun: _bottomRun,
    );
    final origin = box.localToGlobal(Offset.zero);
    return [
      for (final p in layout.positions)
        (
          tile: p.tile,
          center:
              origin +
              boardOrigin(
                size,
                layout.bounds,
              ) +
              p.offset,
          scale: layout.scale * 0.90,
          horizontal: p.horizontal,
          flipped: p.isFlipped,
        ),
    ];
  }

  void _playReveal(VoidCallback onDone) {
    final table = _rectOf(_tableKey);
    if (table == null) {
      onDone();
      return;
    }
    final hands = [
      List<DominoTile>.of(_hand),
      List<DominoTile>.of(_players[1].hand),
      List<DominoTile>.of(_players[2].hand),
      List<DominoTile>.of(_players[3].hand),
    ];
    setState(() => _revealing = true);
    _revealRun?.dispose();
    _revealRun = HandReveal.play(
      context: context,
      vsync: this,
      table: table,
      rack: _rectOf(_rackKey),
      hands: hands,
      boardTiles: _boardTileSpecs(),
    );
    if (_revealRun == null) {
      setState(() => _revealing = false);
      onDone();
      return;
    }
    _revealRun!.done.whenComplete(() {
      _revealRun = null;
      if (!mounted) return;
      setState(() => _revealing = false);
      onDone();
    });
  }

  int _teamPips(int team) {
    var total = 0;
    for (var i = 0; i < _players.length; i++) {
      if (_players[i].team != team) continue;
      final hand = i == 0 ? _hand : _players[i].hand;
      total += hand.fold<int>(0, (sum, t) => sum + t.top + t.bottom);
    }
    return total;
  }

  void _showHandOver(int winningTeam, int points) {
    final isWin = winningTeam == 0;
    final isGameOver =
        _team1Score >= _targetScore || _team2Score >= _targetScore;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => HandOverDialog(
        isWin: isWin,
        isGameOver: isGameOver,
        winningTeam: winningTeam,
        points: points,
        team1Score: _team1Score,
        team2Score: _team2Score,
        targetScore: _targetScore,
        onPrimary: () {
          Navigator.pop(ctx);
          if (isGameOver) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const GameScreen()),
            );
          } else {
            _startNextHand();
          }
        },
        onMenu: () {
          Navigator.pop(ctx);
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ValueListenableBuilder<double>(
              valueListenable: _turnProgress,
              builder: (context, progress, _) => ScoreHeader(
                team1Score: _team1Score,
                team2Score: _team2Score,
                targetScore: _targetScore,
                turnFraction: progress,
                onMenu: _confirmLeave,
                team1Key: _team1Key,
                team2Key: _team2Key,
              ),
            ),
            Expanded(
              child: ClipRect(
                child: Stack(
                  key: _tableKey,
                  children: [
                    const Positioned.fill(child: _Felt()),
                    // Drop anywhere on the table: if only one end fits, play there.
                    Positioned.fill(
                      child: DragTarget<DominoTile>(
                        onWillAcceptWithDetails: (details) {
                          if (_current != 0 || _handOver || _animating) {
                            return false;
                          }
                          final ends = _endsFor(details.data);
                          return ends.left != ends.right;
                        },
                        onAcceptWithDetails: (details) {
                          final ends = _endsFor(details.data);
                          _onDropTile(
                            details.data,
                            ends.left ? 'left' : 'right',
                            details.offset,
                          );
                        },
                        builder: (context, candidate, rejected) =>
                            const SizedBox.expand(),
                      ),
                    ),
                    // Partner across the table (team 1).
                    Positioned(
                      key: _seatKeys[2],
                      top: 4,
                      left: 0,
                      right: 0,
                      child: ValueListenableBuilder<double>(
                        valueListenable: _turnProgress,
                        builder: (context, progress, _) => OpponentSeat(
                          player: _players[2],
                          playerIndex: 2,
                          isCurrentTurn: _current == 2,
                          turnProgress: _current == 2 ? progress : 1,
                          hideTiles: _revealing,
                          avatarKey: _topAvatarKey,
                        ),
                      ),
                    ),
                    // Left opponent (team 2).
                    Positioned(
                      key: _seatKeys[1],
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: ValueListenableBuilder<double>(
                          valueListenable: _turnProgress,
                          builder: (context, progress, _) => OpponentSeat(
                            player: _players[1],
                            playerIndex: 1,
                            isCurrentTurn: _current == 1,
                            turnProgress: _current == 1 ? progress : 1,
                            direction: Axis.vertical,
                            hideTiles: _revealing,
                          ),
                        ),
                      ),
                    ),
                    // Right opponent (team 2).
                    Positioned(
                      key: _seatKeys[3],
                      right: 0,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: ValueListenableBuilder<double>(
                          valueListenable: _turnProgress,
                          builder: (context, progress, _) => OpponentSeat(
                            player: _players[3],
                            playerIndex: 3,
                            isCurrentTurn: _current == 3,
                            turnProgress: _current == 3 ? progress : 1,
                            direction: Axis.vertical,
                            hideTiles: _revealing,
                          ),
                        ),
                      ),
                    ),
                    // The domino board.
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(42, 39, 42, 11),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Opacity(
                              opacity: _revealing ? 0 : 1,
                              child: GameBoard(
                                key: _boardKey,
                                board: _board,
                                smart: true,
                                topRun: _topRun,
                                bottomRun: _bottomRun,
                                tileBuilder:
                                    (
                                      tile, {
                                      required bool horizontal,
                                      required bool isFlipped,
                                      required double scale,
                                    }) {
                                      // A little air keeps the sprite's
                                      // shadow and side off the neighbour.
                                      return SpriteDominoTile(
                                        tile: tile,
                                        horizontal: horizontal,
                                        isFlipped: isFlipped,
                                        scale: scale * 0.98,
                                      );
                                    },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    ..._buildEndTargets(),
                  ],
                ),
              ),
            ),
            ValueListenableBuilder<double>(
              valueListenable: _turnProgress,
              builder: (context, progress, _) => PlayerRack(
                key: _rackKey,
                hand: _hand,
                playable: _playable,
                isMyTurn: _current == 0,
                turnFraction: progress,
                hideTiles: _revealing,
                onTileTap: _playHuman,
                onSort: () {},
                onReorder: _reorderHand,
                onPlayDragChanged: (tile) {
                  if (_dragTile != tile) {
                    setState(() => _dragTile = tile);
                  }
                },
                onAvatarTap: _openEmotes,
                avatarKey: _rackAvatarKey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Green felt table background.
/// Public felt background shared by the game and matchmaking screens.
class FeltTable extends StatelessWidget {
  const FeltTable({super.key});

  @override
  Widget build(BuildContext context) => const _Felt();
}

class _Felt extends StatelessWidget {
  const _Felt();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/ui/table_light_blue.jpg',
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stack) => const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF8FDFFF),
                  Color(0xFF5BBAF0),
                  Color(0xFF2E94EA),
                  Color(0xFF1E6FC4),
                ],
                stops: [0.0, 0.35, 0.7, 1.0],
              ),
            ),
          ),
        ),
        // Soft white glow keeps the table bright.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.25),
              radius: 1.0,
              colors: [Color(0x16FFFFFF), Color(0x08FFFFFF), Color(0x00FFFFFF)],
              stops: [0.0, 0.5, 1.0],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x10FFFFFF), Color(0x00FFFFFF), Color(0x140B2A5B)],
              stops: [0.0, 0.55, 1.0],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              radius: 1.0,
              colors: [Color(0x00000000), Color(0x160B2A5B)],
              stops: [0.65, 1.0],
            ),
          ),
        ),
      ],
    );
  }
}
