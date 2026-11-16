import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/domino_tile.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../theme/arcade_ui.dart';
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
  /// Stable id for this app session, so the server can put us back in a game
  /// we left without quitting.
  static final String _clientId =
      'c${DateTime.now().microsecondsSinceEpoch}${math.Random().nextInt(1 << 30)}';

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Map<String, dynamic>? _state;
  int _seat = -1;
  int _waiting = 1;
  int _secondsRemaining = 20;
  String _phase = 'ready';
  /// Players currently in the matchmaking queue, in join order (so index =
  /// seat once the room starts). Sent by the server with 'queued'.
  List<Map<String, dynamic>> _queuePlayers = [];
  String? _error;
  DominoTile? _selected;
  DominoTile? _dragTile;
  final GlobalKey _boardKey = GlobalKey();
  final GlobalKey _tableKey = GlobalKey();
  final GlobalKey _rackKey = GlobalKey();
  final GlobalKey _team1Key = GlobalKey();
  final GlobalKey _team2Key = GlobalKey();
  ScoreFlyRun? _scoreFlyRun;
  BrickThrowRun? _brickRun;
  EmoteBurstRun? _emoteBurst;
  final GlobalKey _rackAvatarKey = GlobalKey();
  final GlobalKey _topAvatarKey = GlobalKey();
  HandRevealRun? _revealRun;
  bool _revealing = false;
  double _topRun = 3;
  double _bottomRun = 3;
  bool _resultRecorded = false;
  bool _resultDialogShown = false;
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
    _revealRun?.dispose();
    _revealRun = null;
    _scoreFlyRun?.dispose();
    _scoreFlyRun = null;
    _brickRun?.dispose();
    _brickRun = null;
    _emoteBurst?.dispose();
    _emoteBurst = null;
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
        // Leaving a game keeps it running; only lobby exits are cancelled.
        if (_state == null) {
          channel.sink.add(jsonEncode({'type': 'cancel'}));
        }
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
          'clientId': _clientId,
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
            final players = message['players'];
            _queuePlayers = players is List
                ? players
                      .whereType<Map>()
                      .map((p) => Map<String, dynamic>.from(p))
                      .toList()
                : const [];
          });
          break;
        case 'start':
          setState(() {
            _phase = 'playing';
            _seat = (message['seat'] as num?)?.toInt() ?? _seat;
            _queuePlayers = const [];
            _resultRecorded = false;
            _resultDialogShown = false;
            _localHand = null;
            _timerTurn = -1;
            _selectedFromRect = null;
            _animating = false;
          });
          _flyEntry?.remove();
          _flyEntry = null;
          _turnProgress.value = 1;
          break;
        case 'state':
        case 'gameover':
          final prevScores = _state?['scores'];
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
            if ((message['board'] as List?)?.isEmpty ?? true) {
              _topRun = 3;
              _bottomRun = 3;
            }
          });
          _syncHandOrder();
          _startTurnTimer(
            (message['turn'] as num?)?.toInt() ?? -1,
            message['status']?.toString() ?? 'playing',
          );
          _syncAutoPass();
          _maybeGrowVerticalRuns();

          // Points fly from the losing seats to the winner's counter.
          final nowScores = message['scores'];
          final ended = message['status']?.toString() == 'handover' ||
              message['type'] == 'gameover';
          if (ended &&
              prevScores is List &&
              nowScores is List &&
              prevScores.length >= 2 &&
              nowScores.length >= 2) {
            final d0 =
                (nowScores[0] as num).toInt() -
                (prevScores[0] as num).toInt();
            final d1 =
                (nowScores[1] as num).toInt() -
                (prevScores[1] as num).toInt();
            if (d0 > 0 || d1 > 0) {
              final winner = d0 >= d1 ? 0 : 1;
              _playScoreFly(winner, d0 >= d1 ? d0 : d1);
            }
          }
          if (message['status']?.toString() == 'handover') {
            final hands = _parseHands(message['allHands']);
            if (hands != null) _playRevealHands(hands);
          }
          if (message['type'] == 'gameover') {
            final hands = _parseHands(message['allHands']);
            if (hands != null) {
              _playRevealHands(
                hands,
                onDone: () {
                  _recordOnlineResult(message);
                  _showResultDialog(message);
                },
              );
            } else {
              _recordOnlineResult(message);
              _showResultDialog(message);
            }
          }
          break;
        case 'emote':
          final emoteSeat = (message['seat'] as num?)?.toInt();
          final emote = message['emote']?.toString();
          if (emoteSeat != null && emote != null && emoteSeat != _seat) {
            _playRemoteEmote(emote, emoteSeat);
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

  /// Screen centres of the tiles already on the board, used by the reveal.
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
    final board = _board;
    if (board.isEmpty) return const [];
    final layout = computeLayout(
      board,
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

  /// Same vertical-run growth as practice, so both boards lay out the same.
  void _maybeGrowVerticalRuns() {
    if (_topRun == 4 && _bottomRun == 4) return;
    final box = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final board = _board;
    if (board.isEmpty) return;
    final next = growVerticalRuns(
      board: board,
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

  List<List<DominoTile>>? _parseHands(dynamic raw) {
    if (raw is! List || raw.length != 4) return null;
    final hands = <List<DominoTile>>[];
    for (final hand in raw) {
      if (hand is! List) return null;
      hands.add([
        for (final item in hand)
          if (item is List && item.length == 2)
            DominoTile((item[0] as num).toInt(), (item[1] as num).toInt()),
      ]);
    }
    return hands;
  }

  Rect? _rectOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Chips fly from the losing team's seats to the winner's score counter.
  void _playScoreFly(int winningTeam, int points) {
    final table = _rectOf(_tableKey);
    if (table == null) return;
    final rack = _rectOf(_rackKey);
    final losing = 1 - winningTeam;
    final mySeat = _seat < 0 ? 0 : _seat;
    final from = <Offset>[];
    for (var s = 0; s < 4; s++) {
      if (s % 2 != losing) continue;
      final side = ((s - mySeat) % 4 + 4) % 4;
      from.add(switch (side) {
        0 => rack?.center ?? Offset(table.center.dx, table.bottom - 14),
        2 => Offset(table.center.dx, table.top + 34),
        1 => Offset(table.left + 30, table.center.dy),
        _ => Offset(table.right - 30, table.center.dy),
      });
    }

    final key = winningTeam == 0 ? _team1Key : _team2Key;
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    final to = box != null && box.hasSize
        ? box.localToGlobal(box.size.center(Offset.zero))
        : const Offset(0, 48);

    _scoreFlyRun?.dispose();
    _scoreFlyRun = ScoreFly.play(
      context: context,
      vsync: this,
      from: from,
      to: to,
      points: points,
    );
  }

  /// Plays the shared end-of-hand reveal. Seats are mapped to the local view:
  /// you at the bottom, then left, top, right.
  void _playRevealHands(
    List<List<DominoTile>> hands, {
    VoidCallback? onDone,
  }) {
    if (_revealRun != null) {
      onDone?.call();
      return;
    }
    final table = _rectOf(_tableKey);
    if (table == null) {
      onDone?.call();
      return;
    }
    final seat = _seat < 0 ? 0 : _seat;
    setState(() => _revealing = true);
    _revealRun = HandReveal.play(
      context: context,
      vsync: this,
      table: table,
      rack: _rectOf(_rackKey),
      hands: hands,
      boardTiles: _boardTileSpecs(),
      sideOfHand: (s) => ((s - seat) % 4 + 4) % 4,
    );
    if (_revealRun == null) {
      setState(() => _revealing = false);
      onDone?.call();
      return;
    }
    _revealRun!.done.whenComplete(() {
      _revealRun = null;
      if (!mounted) return;
      setState(() => _revealing = false);
      onDone?.call();
    });
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

  Offset? _centreOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  Offset _sidePoint(int side, Rect table, Rect? rack) {
    switch (side) {
      case 0:
        return rack?.center ?? Offset(table.center.dx, table.bottom - 14);
      case 2:
        return Offset(table.center.dx, table.top + 44);
      case 1:
        return Offset(table.left + 28, table.center.dy);
      default:
        return Offset(table.right - 28, table.center.dy);
    }
  }

  void _playRemoteEmote(String emote, int seat) {
    final table = _rectOf(_tableKey);
    if (table == null) return;
    final rack = _rectOf(_rackKey);
    final my = _seat < 0 ? 0 : _seat;
    final side = ((seat - my) % 4 + 4) % 4;
    final from = _sidePoint(side, table, rack);
    final to = _sidePoint((side + 2) % 4, table, rack);
    if (emote == 'brick') {
      _brickRun?.dispose();
      _brickRun = BrickThrow.play(
        context: context,
        vsync: this,
        from: from,
        to: to,
      );
    } else {
      _playBurst(emote == 'laugh' ? 'HA HA HA' : 'GG WP', from);
    }
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
      _playBurst(text, origin);
      _send({'type': 'emote', 'emote': choice});
    }
  }

  void _playBurst(String text, Offset at) {
    _emoteBurst?.dispose();
    _emoteBurst = EmoteBurst.play(
      context: context,
      vsync: this,
      at: at,
      text: text,
    );
  }

  void _throwBrick() {
    final rack = _rectOf(_rackKey);
    final table = _rectOf(_tableKey);
    if (rack == null || table == null) return;
    final from =
        _centreOf(_rackAvatarKey) ?? Offset(rack.left + 28, rack.top + 26);
    final to =
        _centreOf(_topAvatarKey) ?? Offset(table.center.dx, table.top + 60);
    _brickRun?.dispose();
    _brickRun = BrickThrow.play(
      context: context,
      vsync: this,
      from: from,
      to: to,
    );
    _send({'type': 'emote', 'emote': 'brick'});
  }

  Future<void> _confirmLeave() async {
    if (_state == null) {
      _leave();
      return;
    }
    final action = await showLeaveGameDialog(context, online: true);
    if (!mounted || action == null || action == 'stay') return;
    if (action == 'quit') {
      _send({'type': 'quit'});
      setState(() => _state = null);
    }
    _leave();
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
    final anchor = boardOrigin(size, bounds);
    return (
      rect: Rect.fromLTWH(
        origin.dx + anchor.dx + placement.offset.dx - w / 2,
        origin.dy + anchor.dy + placement.offset.dy - h / 2,
        w,
        h,
      ),
      horizontal: placement.horizontal,
      flipped: placement.isFlipped,
    );
  }

  Rect? _targetRect(DominoTile tile, String side) => _previewRectFor(tile, side);

  /// Where the tile goes, drawn against the board as it is right now (the
  /// board re-centres when the tile is placed, so the raw placement slot
  /// would overlap the tile it attaches to).
  Rect? _previewRectFor(DominoTile tile, String side) {
    final box = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final size = box.size;

    final connected = side == 'left' ? _left : _right;
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

    // The tile the new one attaches to: the last tile on that side, or the
    // centre tile when the side is still empty.
    var end = _board.first;
    for (final p in _board) {
      if (p.side == side) end = p;
    }

    TilePlacement? curEnd;
    for (final p in cur.positions) {
      if (p.tile.top == end.tile.top && p.tile.bottom == end.tile.bottom) {
        curEnd = p;
        break;
      }
    }
    TilePlacement? nextEnd;
    TilePlacement? nextNew;
    for (final p in next.positions) {
      if (p.tile.top == end.tile.top && p.tile.bottom == end.tile.bottom) {
        nextEnd = p;
      }
      if (p.tile.top == tile.top && p.tile.bottom == tile.bottom) {
        nextNew = p;
      }
    }
    if (curEnd == null || nextEnd == null || nextNew == null) {
      return _placementFor(tile, side, local: true)?.rect;
    }

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
    final toScale = ((to.height / (horizontal ? 60 : 130)) * 0.98)
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
    final tile = _dragTile ?? _selected;
    if (tile == null) return const [];
    if (!_myTurn || _animating) return const [];

    return [
      for (final side in const ['left', 'right'])
        if (_fitsEnd(tile, side))
          if (_targetRect(tile, side) case final rect?)
            _endTarget(tile, side, rect),
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

  Widget _endTarget(DominoTile tile, String side, Rect boardRect) {
    final rect = _tableRect(boardRect);
    const touch = 16.0; // bigger tap area, the marker itself stays in the slot
    const inset = 4.0; // keeps the border off the neighbouring tiles
    return Positioned.fromRect(
      rect: rect.inflate(touch),
      child: DragTarget<DominoTile>(
        onWillAcceptWithDetails: (details) => _fitsEnd(details.data, side),
        onAcceptWithDetails: (details) => _play(
          details.data,
          side,
          fromRect: Rect.fromLTWH(details.offset.dx, details.offset.dy, 40, 88),
        ),
        builder: (context, candidate, rejected) {
          final hover = candidate.isNotEmpty;
          return GestureDetector(
            onTap: () => _play(tile, side, fromRect: _selectedFromRect),
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
    // Fade + rise the lobby card in once; later rebuilds (countdown, players
    // joining) do not replay it.
    return _LobbyEntrance(child: _buildMatchmaking());
  }

  /// Four 2v2 seats in join order (seat index = team slot: even = blue,
  /// odd = red). Unknown players show as open seats.
  List<_LobbySeat> _lobbySeats() {
    final seats = <_LobbySeat>[];
    for (var i = 0; i < 4; i++) {
      if (i < _queuePlayers.length) {
        final p = _queuePlayers[i];
        seats.add(
          _LobbySeat(
            name: (p['name'] ?? 'Player').toString(),
            you: p['you'] == true,
            bot: p['bot'] == true,
          ),
        );
      } else if (_queuePlayers.isEmpty && i == 0) {
        seats.add(_LobbySeat(name: _lobbyName, you: true));
      } else {
        seats.add(const _LobbySeat());
      }
    }
    return seats;
  }

  String get _lobbyName {
    final typed = _nameController.text.trim();
    if (typed.isNotEmpty) return typed;
    final saved = PlayerProfile.instance.name.trim();
    return saved.isEmpty ? 'YOU' : saved;
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
                      const _LobbyHeader(),
                      const SizedBox(height: 14),
                      _TeamBoard(seats: _lobbySeats()),
                      const SizedBox(height: 10),
                      Text(
                        'We’ll wait 20 seconds for players, then fill any open seats with bots.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: ArcadeColors.navy.withValues(alpha: 0.7),
                          fontSize: 11.5,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 18),
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
                              child: _MiniButton(
                                'REGISTER',
                                () => _sendAuth('register'),
                                const [ArcadeColors.skyTop, ArcadeColors.skyMid],
                                ArcadeColors.skyDeep,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _MiniButton(
                                'LOGIN',
                                () => _sendAuth('login'),
                                const [
                                  ArcadeColors.green,
                                  ArcadeColors.greenDeep,
                                ],
                                ArcadeColors.greenEdge,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _MiniButton(
                                'RANKS',
                                () {
                                  _ensureConnected().then((_) {
                                    _send({'type': 'leaderboard'});
                                  }).catchError((error) {
                                    _connectionFailed(error);
                                  });
                                },
                                const [ArcadeColors.gold, ArcadeColors.goldDeep],
                                ArcadeColors.goldEdge,
                                textColor: ArcadeColors.navy,
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
                              child: _MiniButton(
                                'AD +50 COINS',
                                () => _watchAd('coins'),
                                const [
                                  ArcadeColors.green,
                                  ArcadeColors.greenDeep,
                                ],
                                ArcadeColors.greenEdge,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _MiniButton(
                                'AD +5 GEMS',
                                () => _watchAd('gems'),
                                const [
                                  ArcadeColors.aqua,
                                  ArcadeColors.aquaDeep,
                                ],
                                const Color(0xFF0B6B5C),
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
                        _QueueStatus(
                          phase: _phase,
                          secondsRemaining: _secondsRemaining,
                          waiting: _waiting,
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ArcadeButton(
                            onTap: _leave,
                            height: 44,
                            depth: 5,
                            radius: 14,
                            faceColors: const [
                              Colors.white,
                              ArcadeColors.frost,
                            ],
                            edgeColor: ArcadeColors.frostEdge,
                            child: const Text(
                              'CANCEL',
                              style: TextStyle(
                                color: ArcadeColors.navy,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.4,
                              ),
                            ),
                          ),
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
                onMenu: _confirmLeave,
                team1Key: _team1Key,
                team2Key: _team2Key,
              ),
            ),
            Expanded(
              child: ClipRect(
                child: Stack(
                  key: _tableKey,
                  clipBehavior: Clip.hardEdge,
                  children: [
                  const Positioned.fill(child: _FeltBackground()),
                  Positioned.fill(
                    child: DragTarget<DominoTile>(
                      onWillAcceptWithDetails: (details) {
                        if (!_myTurn || _animating) return false;
                        final left = _fitsEnd(details.data, 'left');
                        final right = _fitsEnd(details.data, 'right');
                        return left != right;
                      },
                      onAcceptWithDetails: (details) {
                        final left = _fitsEnd(details.data, 'left');
                        _play(
                          details.data,
                          left ? 'left' : 'right',
                          fromRect: Rect.fromLTWH(
                            details.offset.dx,
                            details.offset.dy,
                            40,
                            88,
                          ),
                        );
                      },
                      builder: (context, candidate, rejected) =>
                          const SizedBox.expand(),
                    ),
                  ),
                  if (_seat >= 0 && players.length == 4) ...[
                    Positioned(
                      top: 4,
                      left: 0,
                      right: 0,
                      child: _opponent(
                        (_seat + 2) % 4,
                        players,
                        counts,
                        Axis.horizontal,
                        layoutIndex: 2,
                        avatarKey: _topAvatarKey,
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
                          layoutIndex: 1,
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
                          layoutIndex: 3,
                        ),
                      ),
                    ),
                  ],
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
                              // Same snake layout as practice.
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
                  ..._endTargets(),
                ],
                ),
              ),
            ),
            ValueListenableBuilder<double>(
              valueListenable: _turnProgress,
              builder: (context, progress, _) => PlayerRack(
                key: _rackKey,
                hand: _localHand ?? _hand,
                playable: _playable,
                isMyTurn: _myTurn,
                turnFraction: progress,
                hideTiles: _revealing,
                onTileTap: _onTileTap,
                onSort: _sortHand,
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

  Widget _opponent(
    int seat,
    List<dynamic> players,
    List<dynamic> counts,
    Axis direction, {
    int layoutIndex = -1,
    Key? avatarKey,
  }) {
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
        layoutIndex: layoutIndex,
        isCurrentTurn: _turn == seat,
        turnProgress: _turn == seat ? progress : 1,
        direction: direction,
        hideTiles: _revealing,
        avatarKey: avatarKey,
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

/// Raised 3D title plate for the lobby card.
class _LobbyHeader extends StatelessWidget {
  const _LobbyHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            ArcadeColors.skyTop,
            ArcadeColors.skyMid,
            ArcadeColors.skyDeep,
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.55), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: ArcadeColors.navyDeep.withValues(alpha: 0.45),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Align(
                alignment: Alignment.topCenter,
                child: FractionallySizedBox(
                  heightFactor: 0.5,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.38),
                          Colors.white.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.groups_rounded, color: Colors.white, size: 26),
                SizedBox(width: 8),
                Text(
                  'FIND A MATCH',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Blue team on top, red team below, two seats each.
class _TeamBoard extends StatelessWidget {
  final List<_LobbySeat> seats;

  const _TeamBoard({required this.seats});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _TeamPanel(
          title: 'BLUE TEAM',
          color: ArcadeColors.skyDeep,
          seats: [seats[0], seats[2]],
        ),
        const SizedBox(height: 10),
        _TeamPanel(
          title: 'RED TEAM',
          color: const Color(0xFFD32F2F),
          seats: [seats[1], seats[3]],
        ),
      ],
    );
  }
}

class _TeamPanel extends StatelessWidget {
  final String title;
  final Color color;
  final List<_LobbySeat> seats;

  const _TeamPanel({
    required this.title,
    required this.color,
    required this.seats,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.28), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.6),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.3,
                ),
              ),
              const Spacer(),
              Text(
                '2v2',
                style: TextStyle(
                  color: color.withValues(alpha: 0.7),
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _SeatSlot(seat: seats[0], color: color)),
              const SizedBox(width: 8),
              Expanded(child: _SeatSlot(seat: seats[1], color: color)),
            ],
          ),
        ],
      ),
    );
  }
}

class _SeatCard extends StatelessWidget {
  final _LobbySeat seat;
  final Color color;

  const _SeatCard({super.key, required this.seat, required this.color});

  @override
  Widget build(BuildContext context) {
    final empty = seat.name.isEmpty;
    final avatarColor = seat.you
        ? PlayerProfile.instance.avatar.color
        : _colorForName(seat.name, color);
    final initial = seat.name.isEmpty
        ? '?'
        : seat.name.substring(0, 1).toUpperCase();

    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Color(0xFFEAF5FF)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: seat.you ? ArcadeColors.gold : Colors.white,
          width: seat.you ? 2 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: ArcadeColors.navy.withValues(alpha: 0.16),
            blurRadius: 6,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: empty ? ArcadeColors.navy.withValues(alpha: 0.08) : null,
              gradient: empty
                  ? null
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color.lerp(avatarColor, Colors.white, 0.35)!,
                        avatarColor,
                        Color.lerp(avatarColor, Colors.black, 0.28)!,
                      ],
                    ),
              border: Border.all(
                color: empty
                    ? color.withValues(alpha: 0.35)
                    : Colors.white,
                width: 1.6,
              ),
            ),
            child: Center(
              child: empty
                  ? Icon(
                      Icons.person_add_alt_1_rounded,
                      color: color.withValues(alpha: 0.55),
                      size: 16,
                    )
                  : Text(
                      initial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  empty ? 'OPEN SEAT' : seat.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: empty
                        ? ArcadeColors.navy.withValues(alpha: 0.45)
                        : ArcadeColors.navy,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  empty
                      ? 'WAITING…'
                      : seat.you
                      ? 'YOU'
                      : seat.bot
                      ? 'BOT'
                      : 'PLAYER',
                  style: TextStyle(
                    color: seat.you
                        ? ArcadeColors.goldEdge
                        : color.withValues(alpha: 0.85),
                    fontSize: 8.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Stable avatar colour per player name (the server does not send avatars yet).
Color _colorForName(String name, Color fallback) {
  if (name.isEmpty) return fallback;
  var hash = 0;
  for (final unit in name.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return kAvatars[hash % kAvatars.length].color;
}

/// Queue status strip: countdown + filled seats.
class _QueueStatus extends StatelessWidget {
  final String phase;
  final int secondsRemaining;
  final int waiting;

  const _QueueStatus({
    required this.phase,
    required this.secondsRemaining,
    required this.waiting,
  });

  @override
  Widget build(BuildContext context) {
    final connecting = phase == 'connecting';
    final starting = phase == 'playing';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: ArcadeColors.navy.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          if (connecting || starting)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation(ArcadeColors.skyDeep),
                backgroundColor: Color(0x1A0B2A5B),
              ),
            )
          else
            _CountdownRing(fraction: secondsRemaining / 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              connecting
                  ? 'CONNECTING TO THE PC…'
                  : starting
                  ? 'STARTING YOUR GAME…'
                  : '$secondsRemaining s  •  $waiting/4 PLAYERS',
              style: const TextStyle(
                color: ArcadeColors.navy,
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small 3D button for the account/leaderboard row.
class _MiniButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final List<Color> faceColors;
  final Color edgeColor;
  final Color textColor;

  const _MiniButton(
    this.label,
    this.onTap,
    this.faceColors,
    this.edgeColor, {
    this.textColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return ArcadeButton(
      onTap: onTap,
      height: 38,
      depth: 4,
      radius: 12,
      faceColors: faceColors,
      edgeColor: edgeColor,
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

/// One 2v2 seat in the lobby board.
class _LobbySeat {
  final String name;
  final bool you;
  final bool bot;

  const _LobbySeat({this.name = '', this.you = false, this.bot = false});
}

/// One-shot fade + rise + slight scale when the lobby opens.
class _LobbyEntrance extends StatelessWidget {
  final Widget child;

  const _LobbyEntrance({required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, t, child) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - t)),
            child: Transform.scale(scale: 0.97 + 0.03 * t, child: child),
          ),
        );
      },
    );
  }
}

/// Seat slot that pops its card in when a player joins the queue.
class _SeatSlot extends StatelessWidget {
  final _LobbySeat seat;
  final Color color;

  const _SeatSlot({required this.seat, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        final scale = Tween<double>(begin: 0.72, end: 1).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
        );
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: scale, child: child),
        );
      },
      child: _SeatCard(
        key: ValueKey('${seat.name}|${seat.you}|${seat.bot}'),
        seat: seat,
        color: color,
      ),
    );
  }
}

/// 20-second ring that drains smoothly, amber then red near the end.
class _CountdownRing extends StatelessWidget {
  final double fraction;

  const _CountdownRing({required this.fraction});

  @override
  Widget build(BuildContext context) {
    final f = fraction.clamp(0.0, 1.0);
    final color = f > 0.45
        ? ArcadeColors.aquaDeep
        : f > 0.2
        ? ArcadeColors.goldDeep
        : const Color(0xFFD32F2F);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: f),
      duration: const Duration(milliseconds: 850),
      curve: Curves.linear,
      builder: (context, value, _) => SizedBox(
        width: 26,
        height: 26,
        child: CircularProgressIndicator(
          value: value,
          strokeWidth: 3.4,
          backgroundColor: const Color(0x1A0B2A5B),
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ),
    );
  }
}
