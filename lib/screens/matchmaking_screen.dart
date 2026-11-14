import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/domino_tile.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../theme/arcade_ui.dart';
import '../widgets/game_board.dart';
import '../widgets/hand_over_dialog.dart';
import '../widgets/opponent_seat.dart';
import '../widgets/player_rack.dart';
import '../widgets/score_header.dart';
import '../widgets/sprite_domino_tile.dart';
import '../services/ad_service.dart';
import '../services/player_profile.dart';
import 'game_screen.dart' show FeltTable;

/// Joins the LAN matchmaker, then shows the authoritative server game.
class MatchmakingScreen extends StatefulWidget {
  /// When true (default) the screen connects and queues immediately, hiding
  /// the account/server setup so the player only sees "finding a match".
  final bool autoJoin;

  const MatchmakingScreen({super.key, this.autoJoin = true});

  @override
  State<MatchmakingScreen> createState() => _MatchmakingScreenState();
}

class _MatchmakingScreenState extends State<MatchmakingScreen>
    with SingleTickerProviderStateMixin {
  final _nameController = TextEditingController(text: 'Player');
  final _serverController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
// ignore: unused_field
  int? _userId; // kept for future server-profile sync
  String? _authToken;
  String? _authMessage;
  List<Map<String, dynamic>> _leaderboardEntries = [];
  int _coins = 0;
  int _gems = 0;
  bool _adWatchedForNext = false;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Map<String, dynamic>? _state;
  int _seat = -1;
  int _waiting = 1;
  int _secondsRemaining = 20;
  String _phase = 'ready';
  String? _error;
  DominoTile? _selected;
  final GlobalKey _boardKey = GlobalKey();
  bool _resultRecorded = false;
  bool _resultDialogShown = false;
  String? _lastPlacedId;
  List<DominoTile>? _localHand;
  Rect? _selectedFromRect;
  bool _animating = false;
  late final AnimationController _flyController;
  OverlayEntry? _flyEntry;
  final ValueNotifier<double> _turnProgress = ValueNotifier<double>(1);
  Timer? _turnTicker;
  Timer? _passTimer;
  int _timerTurn = -1;

  /// Credits the finished online match to the local profile once.
  @override
  void initState() {
    super.initState();
    _flyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _nameController.text = PlayerProfile.instance.name;
    _usernameController.text = PlayerProfile.instance.name.toLowerCase();
    final baseHost = Uri.base.host;
    _serverController.text = baseHost.isEmpty
        ? 'domino-server.taild9d968.ts.net'
        : baseHost;
    if (widget.autoJoin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _joinQueue();
      });
    }
  }

  @override
  void dispose() {
    _turnTicker?.cancel();
    _passTimer?.cancel();
    _flyEntry?.remove();
    _flyEntry = null;
    _flyController.dispose();
    _turnProgress.dispose();
    _nameController.dispose();
    _serverController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _subscription?.cancel();
    final channel = _channel;
    if (channel != null) {
      try {
        channel.sink.add(
          jsonEncode({'type': _state == null ? 'cancel' : 'leave'}),
        );
        unawaited(channel.sink.close());
      } catch (_) {
        // The connection may already have closed.
      }
    }
    super.dispose();
  }

  Future<void> _joinQueue() async {
    if (_phase == 'connecting' || _phase == 'queue' || _phase == 'playing') {
      return;
    }
    final rawHost = _serverController.text.trim().isEmpty
        ? (Uri.base.host.isEmpty ? '127.0.0.1' : Uri.base.host)
        : _serverController.text.trim();
    final isLocal = rawHost == '127.0.0.1' ||
        rawHost == 'localhost' ||
        rawHost == '0.0.0.0';
    final scheme = (Uri.base.scheme == 'https' || !isLocal) ? 'wss' : 'ws';
    final port = isLocal ? 8080 : null;
    // Reuse the authenticated connection when register/login already opened
    // one, otherwise the server sees a fresh anonymous socket.
    final channel = _channel ??
        WebSocketChannel.connect(
          Uri(scheme: scheme, host: rawHost, port: port),
        );
    final isNew = _channel == null;
    _channel = channel;
    setState(() {
      _phase = 'connecting';
      _error = null;
      _secondsRemaining = 20;
      _adWatchedForNext = false;
    });

    if (isNew) {
      _subscription = channel.stream.listen(
      _onServerMessage,
      onError: (Object error) => _connectionFailed(error),
      onDone: () {
        if (mounted && _phase != 'playing') {
          _connectionFailed('The game server disconnected.');
        }
      },
    );
    }

    try {
      await channel.ready;
      channel.sink.add(
        jsonEncode({
          'type': 'join',
          'name': _nameController.text.trim().isEmpty
              ? PlayerProfile.instance.name
              : _nameController.text.trim(),
          if (_authToken != null) 'token': _authToken,
        }),
      );
    } catch (error) {
      _connectionFailed(error);
    }
  }

  void _onServerMessage(dynamic raw) {
    if (!mounted) return;
    try {
      final message = jsonDecode(raw as String) as Map<String, dynamic>;
      switch (message['type']) {
        case 'queued':
          setState(() {
            _phase = 'queue';
            _waiting = (message['waiting'] as num?)?.toInt() ?? _waiting;
            _secondsRemaining =
                (message['secondsRemaining'] as num?)?.toInt() ??
                _secondsRemaining;
          });
          break;
        case 'start':
          setState(() {
            _phase = 'playing';
            _seat = (message['seat'] as num?)?.toInt() ?? _seat;
            _resultRecorded = false;
            _resultDialogShown = false;
            _localHand = null;
            _timerTurn = -1;
            _lastPlacedId = null;
            _selectedFromRect = null;
            _animating = false;
          });
          _flyEntry?.remove();
          _flyEntry = null;
          _turnProgress.value = 1;
          break;
        case 'state':
        case 'gameover':
          final incomingBoard = message['board'];
          String? newlyPlaced;
          if (incomingBoard is List &&
              incomingBoard.length > _board.length &&
              incomingBoard.isNotEmpty) {
            final last = incomingBoard.last;
            if (last is Map) {
              newlyPlaced = '${last['a']}-${last['b']}';
            }
          }
          setState(() {
            _phase = 'playing';
            _state = message;
            _seat = (message['you'] as num?)?.toInt() ?? _seat;
            _selected = null;
            _selectedFromRect = null;
            if (newlyPlaced != null) _lastPlacedId = newlyPlaced;
          });
          _syncHandOrder();
          _startTurnTimer(
            (message['turn'] as num?)?.toInt() ?? -1,
            message['status']?.toString() ?? 'playing',
          );
          _syncAutoPass();
          if (message['type'] == 'gameover') {
            _recordOnlineResult(message);
            _showResultDialog(message);
          }
          break;
        case 'auth':
          if (message['ok'] == true) {
            setState(() {
              _userId = (message['userId'] as num?)?.toInt();
              _authToken = message['token']?.toString();
              _authMessage = 'Logged in as ${message['username']}';
              if (_nameController.text.trim().isEmpty) {
                _nameController.text = message['username']?.toString() ?? 'Player';
              }
              _send({'type': 'wallet'});
            });
          } else {
            _connectionFailed(message['message']?.toString() ?? 'Auth failed.');
          }
          break;
        case 'leaderboard':
          setState(() {
            _leaderboardEntries = (message['entries'] as List? ?? [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          });
          _showLeaderboardDialog();
          break;
        case 'wallet':
          setState(() {
            _coins = (message['coins'] as num?)?.toInt() ?? _coins;
            _gems = (message['gems'] as num?)?.toInt() ?? _gems;
          });
          break;
        case 'error':
          _connectionFailed(message['message']?.toString() ?? 'Server error.');
          break;
      }
    } catch (error) {
      _connectionFailed('Could not read the server response: $error');
    }
  }

  /// Keeps a stable local order for the hand so the player can reorder and
  /// sort it without fighting every server state update.
  void _syncHandOrder() {
    final server = _hand;
    final previous = _localHand ?? const <DominoTile>[];
    final kept = [for (final t in previous) if (server.contains(t)) t];
    final added = [for (final t in server) if (!kept.contains(t)) t];
    _localHand = [...kept, ...added];
  }

  void _sortHand() {
    if (_animating) return;
    setState(() {
      final hand = [...(_localHand ?? _hand)];
      hand.sort((a, b) {
        if (a.isDouble != b.isDouble) return a.isDouble ? -1 : 1;
        final byPips = (b.top + b.bottom).compareTo(a.top + a.bottom);
        return byPips != 0 ? byPips : a.top.compareTo(b.top);
      });
      _localHand = hand;
    });
  }

  void _reorderHand(int oldIndex, int newIndex) {
    if (_animating) return;
    setState(() {
      final hand = [...(_localHand ?? _hand)];
      if (oldIndex < 0 || oldIndex >= hand.length) return;
      final tile = hand.removeAt(oldIndex);
      hand.insert(newIndex.clamp(0, hand.length), tile);
      _localHand = hand;
    });
  }

  /// A fresh 20s visual timer for the active seat.
  void _startTurnTimer(int turn, String status) {
    if (status != 'playing') {
      _turnTicker?.cancel();
      _turnProgress.value = 0;
      return;
    }
    if (turn == _timerTurn) return;
    _timerTurn = turn;
    _turnTicker?.cancel();
    _turnProgress.value = 1;
    var elapsed = 0.0;
    _turnTicker = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      elapsed += 0.1;
      final value = (1 - elapsed / 20).clamp(0.0, 1.0);
      _turnProgress.value = value;
      if (value > 0) return;
      timer.cancel();
      // Time is up on your turn: auto-play a legal tile, otherwise pass.
      if (!mounted || _animating || !_myTurn) return;
      final playable = _playable;
      if (playable.isEmpty) {
        _send({'type': 'pass'});
      } else {
        final tile = playable.first;
        final fitsLeft = _left >= 0 && tile.matches(_left);
        _play(tile, fitsLeft ? 'left' : 'right');
      }
    });
  }

  /// Passing is automatic when the player has no legal tile.
  void _syncAutoPass() {
    _passTimer?.cancel();
    if (!_myTurn || _playable.isNotEmpty) return;
    _passTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted || !_myTurn || _playable.isNotEmpty) return;
      _send({'type': 'pass'});
    });
  }

  void _showResultDialog(Map<String, dynamic> message) {
    if (_resultDialogShown) return;
    final scores = message['scores'] as List?;
    if (scores == null || scores.length < 2) return;
    _resultDialogShown = true;
    final s0 = (scores[0] as num).toInt();
    final s1 = (scores[1] as num).toInt();
    final winner = s0 >= 100 ? 0 : (s1 >= 100 ? 1 : -1);
    if (winner < 0) return;
    final myTeam = _seat < 0 ? 0 : _seat % 2;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => HandOverDialog(
        isWin: myTeam == winner,
        isGameOver: true,
        winningTeam: winner,
        points: winner == 0 ? s0 : s1,
        team1Score: s0,
        team2Score: s1,
        targetScore: 100,
        onPrimary: () {
          Navigator.pop(ctx);
          _leave();
        },
        onMenu: () {
          Navigator.pop(ctx);
          _leave();
        },
      ),
    );
  }

  void _recordOnlineResult(Map<String, dynamic> message) {
    if (_resultRecorded) return;
    final scores = message['scores'] as List?;
    if (scores == null || scores.length < 2) return;
    _resultRecorded = true;
    final s0 = (scores[0] as num).toInt();
    final s1 = (scores[1] as num).toInt();
    final winner = s0 >= 100 ? 0 : (s1 >= 100 ? 1 : -1);
    if (winner < 0) return;
    PlayerProfile.instance.recordMatch(
      win: (_seat % 2) == winner,
      scoreXp: (s0 + s1) ~/ 10,
    );
  }

  void _connectionFailed(Object error) {
    if (!mounted) return;
    setState(() {
      _phase = 'error';
      _error = '$error';
    });
  }

  Future<void> _ensureConnected() async {
    if (_channel != null) return;
    final rawHost = _serverController.text.trim().isEmpty
        ? (Uri.base.host.isEmpty ? '127.0.0.1' : Uri.base.host)
        : _serverController.text.trim();
    final isLocal = rawHost == '127.0.0.1' ||
        rawHost == 'localhost' ||
        rawHost == '0.0.0.0';
    final scheme = (Uri.base.scheme == 'https' || !isLocal) ? 'wss' : 'ws';
    final port = isLocal ? 8080 : null;
    final channel = WebSocketChannel.connect(
      Uri(scheme: scheme, host: rawHost, port: port),
    );
    _channel = channel;
    _subscription = channel.stream.listen(
      _onServerMessage,
      onError: (Object error) => _connectionFailed(error),
      onDone: () {
        if (mounted && _phase != 'playing') {
          _connectionFailed('The game server disconnected.');
        }
      },
    );
    await channel.ready;
  }

  void _sendAuth(String type) {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _authMessage = 'Enter username and password.');
      return;
    }
    _ensureConnected().then((_) {
      _send({'type': type, 'username': username, 'password': password});
    }).catchError((error) {
      _connectionFailed(error);
    });
  }

  void _showLeaderboardDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leaderboard'),
        content: SizedBox(
          width: 320,
          height: 300,
          child: ListView.builder(
            itemCount: _leaderboardEntries.length,
            itemBuilder: (context, index) {
              final e = _leaderboardEntries[index];
              return ListTile(
                leading: Text('${index + 1}'),
                title: Text(e['username']?.toString() ?? ''),
                subtitle: Text(
                  'W ${e['wins']}  L ${e['losses']}  Score ${e['totalScore']}',
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _watchAd(String rewardType) async {
    final ok = await adService.showRewardedAd(rewardType: rewardType);
    if (!ok) return;
    _ensureConnected().then((_) {
      _send({'type': 'ad_reward', 'rewardType': rewardType});
    }).catchError((error) {
      _connectionFailed(error);
    });
  }

  Future<void> _watchAdToContinue() async {
    await adService.showInterstitial();
    _adWatchedForNext = true;
    _send({'type': 'ad_reward', 'rewardType': 'continue'});
    setState(() => _authMessage = 'Ad watched. You can join again.');
  }

  void _leave() {
    Navigator.of(context).pop();
  }

  void _send(Map<String, Object?> message) {
    final channel = _channel;
    if (channel == null) return;
    try {
      channel.sink.add(jsonEncode(message));
    } catch (error) {
      _connectionFailed(error);
    }
  }

  List<DominoTile> get _hand {
    final raw = _state?['hand'];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is List && item.length == 2)
          DominoTile((item[0] as num).toInt(), (item[1] as num).toInt()),
    ];
  }

  List<PlacedTile> get _board {
    final raw = _state?['board'];
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map)
          PlacedTile(
            DominoTile((item['a'] as num).toInt(), (item['b'] as num).toInt()),
            item['side']?.toString() ?? 'right',
            (item['conn'] as num?)?.toInt() ?? 0,
          ),
    ];
  }

  int get _left => (_state?['left'] as num?)?.toInt() ?? -1;
  int get _right => (_state?['right'] as num?)?.toInt() ?? -1;
  int get _turn => (_state?['turn'] as num?)?.toInt() ?? -1;
  bool get _myTurn => _state?['status'] == 'playing' && _turn == _seat;

  Set<DominoTile> get _playable {
    if (!_myTurn) return const {};
    if (_board.isEmpty) return _hand.toSet();
    return _hand
        .where((tile) => tile.matches(_left) || tile.matches(_right))
        .toSet();
  }

  void _onTileTap(DominoTile tile, Rect? fromRect) {
    if (!_myTurn || _animating || !_playable.contains(tile)) return;
    if (_board.isEmpty) {
      _play(tile, 'right', fromRect: fromRect);
      return;
    }
    setState(() {
      _selected = _selected == tile ? null : tile;
      _selectedFromRect = _selected == null ? null : fromRect;
    });
  }

  bool _fitsEnd(DominoTile tile, String side) =>
      tile.matches(side == 'left' ? _left : _right);

  /// Where [tile] lands after playing it on [side]. Board-local by default,
  /// global (screen) coordinates when [local] is false.
  ({Rect rect, bool horizontal, bool flipped})? _placementFor(
    DominoTile tile,
    String side, {
    required bool local,
  }) {
    final ctx = _boardKey.currentContext;
    final box = ctx?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final size = box.size;
    final origin = local ? Offset.zero : box.localToGlobal(Offset.zero);
    final connected = side == 'left' ? _left : _right;
    final layout = computeLayout(
      [..._board, PlacedTile(tile, side, connected)],
      maxWidth: size.width,
      maxHeight: size.height,
    );
    final placement = layout.positions.firstWhere((p) => p.tile == tile);
    final bounds = layout.bounds;
    final scale = layout.scale;
    final w = (placement.horizontal ? 130.0 : 60.0) * scale;
    final h = (placement.horizontal ? 60.0 : 130.0) * scale;
    final left =
        (size.width - bounds.width) / 2 +
        placement.offset.dx -
        bounds.left -
        w / 2;
    final top =
        (size.height - bounds.height) / 2 +
        placement.offset.dy -
        bounds.top -
        h / 2;
    return (
      rect: Rect.fromLTWH(origin.dx + left, origin.dy + top, w, h),
      horizontal: placement.horizontal,
      flipped: placement.isFlipped,
    );
  }

  Rect? _targetRect(DominoTile tile, String side) =>
      _placementFor(tile, side, local: true)?.rect;

  void _flyTile(
    DominoTile tile,
    Rect from,
    ({Rect rect, bool horizontal, bool flipped}) target,
    VoidCallback onDone,
  ) {
    final overlay = Overlay.of(context);
    final horizontal = target.horizontal;
    final flipped = target.flipped;
    final to = target.rect;
    final fromScale = (from.height / 130).clamp(0.2, 1.0).toDouble();
    final toScale = (to.height / (horizontal ? 60 : 130))
        .clamp(0.2, 1.0)
        .toDouble();
    final targetTurns = (horizontal ? 1 : 0) + (flipped ? 2 : 0);
    var targetAngle = targetTurns * math.pi / 2;
    if (targetAngle > math.pi) targetAngle -= math.pi * 2;
    var angleDelta = targetAngle;
    if (angleDelta > math.pi) angleDelta -= math.pi * 2;
    if (angleDelta < -math.pi) angleDelta += math.pi * 2;

    final hi = math.max(tile.top, tile.bottom);
    final lo = math.min(tile.top, tile.bottom);
    final face = 'assets/tiles/t1d$hi$lo.png';

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
            final angle = angleDelta * t;
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
      _flyEntry?.remove();
      _flyEntry = null;
      if (!mounted) return;
      onDone();
    });
  }

  List<Widget> _endTargets() {
    final tile = _selected;
    if (tile == null || _animating || !_myTurn) return const [];
    return [
      for (final side in const ['left', 'right'])
        if (_fitsEnd(tile, side))
          if (_targetRect(tile, side) case final rect?)
            Positioned.fromRect(
              rect: rect.inflate(6),
              child: GestureDetector(
                onTap: () => _play(
                  tile,
                  side,
                  fromRect: _selectedFromRect,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD700).withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFFFFD700),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.5),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    color: Color(0xFFFFD700),
                    size: 26,
                  ),
                ),
              ),
            ),
    ];
  }

  void _play(DominoTile tile, String side, {Rect? fromRect}) {
    if (_animating) return;
    final target = fromRect == null
        ? null
        : _placementFor(tile, side, local: false);
    if (fromRect == null || target == null) {
      _sendPlay(tile, side);
      return;
    }
    setState(() {
      _selected = null;
      _selectedFromRect = null;
      _animating = true;
      // Hide it from the hand while it is in the air.
      _localHand = [...(_localHand ?? _hand)]..remove(tile);
    });
    _flyTile(tile, fromRect, target, () {
      if (!mounted) return;
      setState(() => _animating = false);
      _sendPlay(tile, side);
    });
  }

  void _sendPlay(DominoTile tile, String side) {
    _send({
      'type': 'play',
      'tile': [tile.top, tile.bottom],
      'side': side,
    });
    setState(() => _selected = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_state != null) return _buildGame();
    return _buildMatchmaking();
  }

  Widget _buildMatchmaking() {
    final joining =
        _phase == 'connecting' || _phase == 'queue' || _phase == 'playing';
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              ArcadeColors.skyTop,
              ArcadeColors.skyMid,
              ArcadeColors.navy,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: ArcadePanel(
                  radius: 26,
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.groups_rounded,
                        color: ArcadeColors.skyDeep,
                        size: 54,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'FIND A MATCH',
                        style: TextStyle(
                          color: ArcadeColors.navy,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'We’ll wait 20 seconds for players, then fill any open seats with bots.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: ArcadeColors.navy.withValues(alpha: 0.7),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (!widget.autoJoin && !joining) ...[
                        TextField(
                          controller: _nameController,
                          maxLength: 16,
                          decoration: InputDecoration(
                            labelText: 'Player name',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _serverController,
                          decoration: InputDecoration(
                            labelText: 'Game server host',
                            hintText: 'domino-server.taild9d968.ts.net',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _usernameController,
                          decoration: InputDecoration(
                            labelText: 'Account username',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: 'Account password',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                        if (_authMessage != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _authMessage!,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _sendAuth('register'),
                                child: const Text('Register'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _sendAuth('login'),
                                child: const Text('Login'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  _ensureConnected().then((_) {
                                    _send({'type': 'leaderboard'});
                                  }).catchError((error) {
                                    _connectionFailed(error);
                                  });
                                },
                                child: const Text('Leaderboard'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Coins: $_coins   Gems: $_gems',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _watchAd('coins'),
                                child: const Text('Ad: +50 coins'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _watchAd('gems'),
                                child: const Text('Ad: +5 gems'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ArcadeButton(
                            onTap: _joinQueue,
                            faceColors: const [
                              ArcadeColors.green,
                              ArcadeColors.greenDeep,
                            ],
                            edgeColor: ArcadeColors.greenEdge,
                            child: const Center(
                              child: Text(
                                'JOIN MATCHMAKING',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ] else ...[
                        const CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation(
                            ArcadeColors.skyDeep,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          _phase == 'connecting'
                              ? 'CONNECTING TO THE PC...'
                              : _phase == 'playing'
                              ? 'STARTING YOUR GAME...'
                              : '$_secondsRemaining  •  $_waiting PLAYER${_waiting == 1 ? '' : 'S'} WAITING',
                          style: const TextStyle(
                            color: ArcadeColors.navy,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextButton(
                          onPressed: _leave,
                          child: const Text('CANCEL'),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],
                      if (!widget.autoJoin)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: TextButton(
                            onPressed: _leave,
                            child: const Text('BACK'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGame() {
    final scores = (_state?['scores'] as List?) ?? const [0, 0];
    final players = (_state?['players'] as List?) ?? const [];
    final counts = (_state?['counts'] as List?) ?? const [0, 0, 0, 0];
    final gameOver = _state?['status'] == 'gameover';
    final selected = _selected;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ValueListenableBuilder<double>(
              valueListenable: _turnProgress,
              builder: (context, progress, _) => ScoreHeader(
                team1Score: (scores[0] as num).toInt(),
                team2Score: (scores[1] as num).toInt(),
                targetScore: 100,
                turnFraction: progress,
                onMenu: _leave,
              ),
            ),
            Expanded(
              child: ClipRect(
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                  const Positioned.fill(child: _FeltBackground()),
                  Positioned.fill(
                    child: DragTarget<DominoTile>(
                      onWillAcceptWithDetails: (details) =>
                          !_animating &&
                          _myTurn &&
                          _playable.contains(details.data),
                      onAcceptWithDetails: (details) {
                        final tile = details.data;
                        final fitsLeft = _left >= 0 && tile.matches(_left);
                        final fitsRight = _right >= 0 && tile.matches(_right);
                        final side = fitsLeft && fitsRight
                            ? (details.offset.dx <
                                    MediaQuery.sizeOf(context).width / 2
                                ? 'left'
                                : 'right')
                            : (fitsLeft ? 'left' : 'right');
                        _play(
                          tile,
                          side,
                          fromRect: Rect.fromCenter(
                            center: details.offset,
                            width: 40,
                            height: 88,
                          ),
                        );
                      },
                      builder: (context, candidate, rejected) =>
                          const SizedBox.expand(),
                    ),
                  ),
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(44, 68, 44, 32),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          GameBoard(
                            key: _boardKey,
                            board: _board,
                            tileBuilder:
                                (
                                  tile, {
                                  required horizontal,
                                  required isFlipped,
                                  required scale,
                                }) {
                                  Widget face = SpriteDominoTile(
                                    tile: tile,
                                    horizontal: horizontal,
                                    isFlipped: isFlipped,
                                    scale: scale,
                                  );
                                  if ('${tile.top}-${tile.bottom}' ==
                                      _lastPlacedId) {
                                    face = TweenAnimationBuilder<double>(
                                      tween: Tween<double>(begin: 0, end: 1),
                                      duration: const Duration(
                                        milliseconds: 260,
                                      ),
                                      curve: Curves.easeOutBack,
                                      builder: (context, t, child) => Opacity(
                                        opacity: t.clamp(0.0, 1.0),
                                        child: Transform.scale(
                                          scale: 0.7 + 0.3 * t,
                                          child: child,
                                        ),
                                      ),
                                      child: face,
                                    );
                                  }
                                  return face;
                                },
                          ),
                          ..._endTargets(),
                        ],
                      ),
                    ),
                  ),
                  if (_seat >= 0 && players.length == 4) ...[
                    Positioned(
                      top: 2,
                      left: 0,
                      right: 0,
                      child: _opponent(
                        (_seat + 2) % 4,
                        players,
                        counts,
                        Axis.horizontal,
                      ),
                    ),
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _opponent(
                          (_seat + 1) % 4,
                          players,
                          counts,
                          Axis.vertical,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: _opponent(
                          (_seat + 3) % 4,
                          players,
                          counts,
                          Axis.vertical,
                        ),
                      ),
                    ),
                  ],
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 8,
                    child: Center(
                      child: Text(
                        gameOver
                            ? (_state?['message']?.toString() ?? 'MATCH OVER')
                            : _myTurn
                            ? 'YOUR TURN'
                            : '${_playerName(_turn, players)} IS PLAYING',
                        style: const TextStyle(
                          color: ArcadeColors.gold,
                          fontWeight: FontWeight.w900,
                          shadows: [Shadow(color: Colors.black, blurRadius: 5)],
                        ),
                      ),
                    ),
                  ),
                ],
                ),
              ),
            ),
            if (gameOver)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: _adWatchedForNext ? _leave : _watchAdToContinue,
                      child: Text(
                        _adWatchedForNext
                            ? 'BACK TO MENU'
                            : 'WATCH AD TO PLAY AGAIN',
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_adWatchedForNext)
                      ElevatedButton(
                        onPressed: _leave,
                        child: const Text('BACK TO MENU'),
                      ),
                  ],
                ),
              )
            else ...[
              if (selected != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Tap a glowing end on the board',
                          style: TextStyle(color: ArcadeColors.gold),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _selected = null),
                        child: const Text('CANCEL'),
                      ),
                    ],
                  ),
                )
              else if (_myTurn && _playable.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  child: ElevatedButton(
                    onPressed: () => _send({'type': 'pass'}),
                    child: const Text('PASS TURN'),
                  ),
                ),
              ValueListenableBuilder<double>(
                valueListenable: _turnProgress,
                builder: (context, progress, _) => PlayerRack(
                  hand: _localHand ?? _hand,
                  playable: _playable,
                  isMyTurn: _myTurn,
                  turnFraction: progress,
                  onTileTap: _onTileTap,
                  onSort: _sortHand,
                  onReorder: _reorderHand,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _opponent(
    int seat,
    List<dynamic> players,
    List<dynamic> counts,
    Axis direction,
  ) {
    final data = players[seat] as Map;
    final handCount = (counts[seat] as num).toInt();
    final player = Player(
      name: data['name']?.toString() ?? 'Player ${seat + 1}',
      team: seat % 2,
      hand: List.generate(handCount, (_) => const DominoTile(0, 0)),
    );
    return ValueListenableBuilder<double>(
      valueListenable: _turnProgress,
      builder: (context, progress, _) => OpponentSeat(
        player: player,
        playerIndex: seat,
        isCurrentTurn: _turn == seat,
        turnProgress: _turn == seat ? progress : 1,
        direction: direction,
      ),
    );
  }

  String _playerName(int seat, List<dynamic> players) {
    if (seat < 0 || seat >= players.length) return 'PLAYER';
    return ((players[seat] as Map)['name'] ?? 'PLAYER')
        .toString()
        .toUpperCase();
  }
}

class _FeltBackground extends StatelessWidget {
  const _FeltBackground();

  @override
  Widget build(BuildContext context) {
    return const FeltTable();
  }
}
