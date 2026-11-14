import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/domino_tile.dart';
import '../models/game_state.dart';
import '../models/player.dart';
import '../theme/arcade_ui.dart';
import '../widgets/game_board.dart';
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

class _MatchmakingScreenState extends State<MatchmakingScreen> {
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

  /// Credits the finished online match to the local profile once.
  @override
  void initState() {
    super.initState();
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
          });
          break;
        case 'state':
        case 'gameover':
          setState(() {
            _phase = 'playing';
            _state = message;
            _seat = (message['you'] as num?)?.toInt() ?? _seat;
            _selected = null;
          });
          if (message['type'] == 'gameover') _recordOnlineResult(message);
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
    if (!_myTurn || !_playable.contains(tile)) return;
    if (_board.isEmpty) {
      _play(tile, 'right');
      return;
    }
    setState(() => _selected = _selected == tile ? null : tile);
  }

  bool _fitsEnd(DominoTile tile, String side) =>
      tile.matches(side == 'left' ? _left : _right);

  Rect? _targetRect(DominoTile tile, String side) {
    final box = _boardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final size = box.size;
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
    return Rect.fromLTWH(left, top, w, h);
  }

  List<Widget> _endTargets() {
    final tile = _selected;
    if (tile == null || !_myTurn) return const [];
    return [
      for (final side in const ['left', 'right'])
        if (_fitsEnd(tile, side))
          if (_targetRect(tile, side) case final rect?)
            Positioned.fromRect(
              rect: rect.inflate(6),
              child: GestureDetector(
                onTap: () => _play(tile, side),
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

  void _play(DominoTile tile, String side) {
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
            ScoreHeader(
              team1Score: (scores[0] as num).toInt(),
              team2Score: (scores[1] as num).toInt(),
              targetScore: 100,
              turnFraction: 1,
              onMenu: _leave,
            ),
            Expanded(
              child: ClipRect(
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                  const Positioned.fill(child: _FeltBackground()),
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
                                }) => SpriteDominoTile(
                                  tile: tile,
                                  horizontal: horizontal,
                                  isFlipped: isFlipped,
                                  scale: scale,
                                ),
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
              PlayerRack(
                hand: _hand,
                playable: _playable,
                isMyTurn: _myTurn,
                turnFraction: 1,
                onTileTap: _onTileTap,
                onSort: () {},
                onReorder: (oldIndex, newIndex) {},
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
    return OpponentSeat(
      player: player,
      playerIndex: seat,
      isCurrentTurn: _turn == seat,
      direction: direction,
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
