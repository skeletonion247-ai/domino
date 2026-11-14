import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

const int kTargetScore = 100;
const int kPlayersPerRoom = 4;
const int kHandSize = 7;

class Tile {
  final int a;
  final int b;
  const Tile(this.a, this.b);

  bool get isDouble => a == b;
  int get pips => a + b;
  bool matches(int v) => a == v || b == v;
  int other(int v) => a == v ? b : a;

  List<int> toJson() => [a, b];
}

class Placed {
  final Tile tile;
  final String side;
  final int connected;

  Placed(this.tile, this.side, this.connected);

  Map<String, dynamic> toJson() => {
        'a': tile.a,
        'b': tile.b,
        'side': side,
        'conn': connected,
      };
}

class Client {
  final WebSocket socket;
  String name;
  int? seat;
  Room? room;
  bool inQueue = false;
  int? userId;
  String? token;

  Client(this.socket, this.name);

  bool get alive => socket.readyState == WebSocket.open;

  void send(Map<String, dynamic> message) {
    if (!alive) return;
    socket.add(jsonEncode(message));
  }

  void sendError(String message) {
    send({'type': 'error', 'message': message});
  }
}

class Room {
  final int id;
  final List<Client?> seats;
  final List<List<Tile>> hands = List.generate(4, (_) => <Tile>[]);
  final List<Placed> board = [];
  final List<int> scores = [0, 0];
  int left = -1;
  int right = -1;
  int turn = 0;
  int passes = 0;
  String status = 'playing';
  String? lastMessage;
  int? winningTeam;
  bool matchRecorded = false;

  Room(this.id, List<Client?> seats) : seats = List.of(seats) {
    for (var i = 0; i < seats.length; i++) {
      final client = seats[i];
      if (client == null) continue;
      client.seat = i;
      client.room = this;
    }
    _deal();
  }

  List<Tile> _set() {
    final tiles = <Tile>[];
    for (var i = 0; i <= 6; i++) {
      for (var j = i; j <= 6; j++) {
        tiles.add(Tile(i, j));
      }
    }
    tiles.shuffle(Random());
    return tiles;
  }

  void _deal() {
    final tiles = _set();
    for (var i = 0; i < 4; i++) {
      hands[i] = tiles.sublist(i * kHandSize, (i + 1) * kHandSize);
    }
    board.clear();
    left = -1;
    right = -1;
    passes = 0;

    // Highest double starts; otherwise seat 0.
    var best = -1;
    turn = 0;
    for (var i = 0; i < 4; i++) {
      for (final tile in hands[i]) {
        if (tile.isDouble && tile.a > best) {
          best = tile.a;
          turn = i;
        }
      }
    }
  }

  bool get boardEmpty => board.isEmpty;
  bool get isBotTurn => seats[turn] == null;

  bool canPlay(Tile tile) {
    if (boardEmpty) return true;
    return tile.matches(left) || tile.matches(right);
  }

  bool handHasMove(int seat) => hands[seat].any(canPlay);

  void _advance() {
    turn = (turn + 1) % 4;
  }

  void play(int seat, Tile tile, String side) {
    if (status != 'playing') throw 'The game is over.';
    if (seat != turn) throw 'It is not your turn.';
    final hand = hands[seat];
    final index = hand.indexWhere((t) => t.a == tile.a && t.b == tile.b);
    if (index < 0) throw 'That tile is not in your hand.';
    if (!canPlay(tile)) throw 'That tile does not fit either end.';
    if (!boardEmpty && side != 'left' && side != 'right') {
      throw 'Choose a side.';
    }

    final connected = boardEmpty
        ? tile.a
        : (side == 'left'
            ? (tile.matches(left) ? left : -1)
            : (tile.matches(right) ? right : -1));
    if (!boardEmpty && connected < 0) {
      throw 'That tile does not fit the ${side} end.';
    }

    hand.removeAt(index);
    final opening = boardEmpty;
    board.add(Placed(tile, opening ? 'right' : side, connected));
    if (opening) {
      left = tile.a;
      right = tile.b;
    } else if (side == 'left') {
      left = tile.other(connected);
    } else {
      right = tile.other(connected);
    }
    passes = 0;

    if (hand.isEmpty) {
      _endHand(seat);
      return;
    }
    _advance();
  }

  void pass(int seat) {
    if (status != 'playing') throw 'The game is over.';
    if (seat != turn) throw 'It is not your turn.';
    if (handHasMove(seat)) throw 'You still have a playable tile.';
    passes++;
    if (passes >= 4) {
      _blocked();
      return;
    }
    _advance();
  }

  void playBotTurn() {
    if (status != 'playing' || !isBotTurn) return;
    final moves = hands[turn].where(canPlay);
    if (moves.isEmpty) {
      pass(turn);
      return;
    }
    final tile = moves.first;
    final fitsLeft = tile.matches(left);
    final fitsRight = tile.matches(right);
    final side = boardEmpty || (fitsLeft && fitsRight)
        ? (Random().nextBool() ? 'left' : 'right')
        : (fitsLeft ? 'left' : 'right');
    play(turn, tile, side);
  }

  void _endHand(int winnerSeat) {
    final team = winnerSeat % 2;
    var points = 0;
    for (var i = 0; i < 4; i++) {
      if (i % 2 != team) {
        points += hands[i].fold<int>(0, (sum, t) => sum + t.pips);
      }
    }
    _award(team, points, winnerSeat, 'Player ${winnerSeat + 1} finished');
  }

  void _blocked() {
    var bestSeat = 0;
    var bestScore = 1 << 30;
    for (var i = 0; i < 4; i++) {
      final score = hands[i].fold<int>(0, (sum, t) => sum + t.pips);
      if (score < bestScore) {
        bestScore = score;
        bestSeat = i;
      }
    }
    final team = bestSeat % 2;
    var points = 0;
    for (var i = 0; i < 4; i++) {
      if (i % 2 != team) {
        points += hands[i].fold<int>(0, (sum, t) => sum + t.pips);
      }
    }
    _award(team, points, bestSeat, 'Blocked');
  }

  void _award(int team, int points, int starter, String reason) {
    scores[team] += points;
    if (scores[team] >= kTargetScore) {
      status = 'gameover';
      winningTeam = team;
      lastMessage = 'Team ${team + 1} wins';
      return;
    }
    _deal();
    turn = starter % 4;
    lastMessage = '$reason · +$points';
  }

  void broadcast(String type, {String? message}) {
    final note = message ?? lastMessage;
    lastMessage = null;
    for (final client in seats) {
      if (client == null || !client.alive) continue;
      final seat = client.seat!;
      client.send({
        'type': type,
        'room': id,
        'you': seat,
        'turn': turn,
        'status': status,
        'scores': scores,
        'left': left,
        'right': right,
        'board': board.map((p) => p.toJson()).toList(),
        'hand': hands[seat].map((t) => t.toJson()).toList(),
        'counts': [for (final h in hands) h.length],
        'players': [
          for (var i = 0; i < seats.length; i++)
            {
              'name': seats[i]?.name ?? 'Bot ${i + 1}',
              'seat': i,
              'team': i % 2,
              'bot': seats[i] == null,
            },
        ],
        if (note != null) 'message': note,
      });
    }
  }
}

class Server {
  final List<Client> queue = [];
  final List<Room> rooms = [];
  final Map<Room, Timer> _botTimers = {};
  int _nextRoom = 1;
  Timer? _matchmakingTimer;
  DateTime? _matchDeadline;
  late Database db;

  void _initDb() {
    final path = Platform.environment['DB_PATH'] ?? 'data/domino.db';
    final dir = Directory(path).parent;
    if (!dir.existsSync()) dir.createSync(recursive: true);
    db = sqlite3.open(path);
    db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        created_at TEXT NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS stats (
        user_id INTEGER PRIMARY KEY,
        games_played INTEGER NOT NULL DEFAULT 0,
        wins INTEGER NOT NULL DEFAULT 0,
        losses INTEGER NOT NULL DEFAULT 0,
        total_score INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (user_id) REFERENCES users(id)
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS matches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        room_id INTEGER NOT NULL,
        winner_team INTEGER NOT NULL,
        scores TEXT NOT NULL,
        played_at TEXT NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS wallet (
        user_id INTEGER PRIMARY KEY,
        coins INTEGER NOT NULL DEFAULT 0,
        gems INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (user_id) REFERENCES users(id)
      );
    ''');
    stdout.writeln('Database ready: $path');
  }

  Future<void> start(int port) async {
    _initDb();
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    server.autoCompress = true;
    stdout.writeln('Domino server listening on port $port');
    await for (final request in server) {
      if (request.uri.path == '/health') {
        request.response
          ..statusCode = 200
          ..write('ok');
        await request.response.close();
        continue;
      }
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        final socket = await WebSocketTransformer.upgrade(request);
        _onSocket(socket);
        continue;
      }
      await _serveStatic(request);
    }
  }

  Future<void> _serveStatic(HttpRequest request) async {
    final root = Platform.environment['STATIC_DIR'] ?? 'web';
    var path = request.uri.path;
    if (path == '/' || path.isEmpty) path = '/index.html';
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.any((s) => s == '..' || s.contains('\\\\'))) {
      request.response.statusCode = 400;
      await request.response.close();
      return;
    }
    var file = File('$root/${segments.join('/')}');
    if (!await file.exists()) {
      file = File('$root/index.html');
      if (!await file.exists()) {
        request.response.statusCode = 404;
        request.response.write('Not found');
        await request.response.close();
        return;
      }
    }
    final ext = path.split('.').last.toLowerCase();
    request.response.headers.contentType = _contentType(ext);
    await request.response.addStream(file.openRead());
    await request.response.close();
  }

  ContentType _contentType(String ext) {
    switch (ext) {
      case 'html':
        return ContentType.html;
      case 'js':
        return ContentType('application', 'javascript', charset: 'utf-8');
      case 'css':
        return ContentType('text', 'css', charset: 'utf-8');
      case 'json':
        return ContentType.json;
      case 'png':
        return ContentType('image', 'png');
      case 'jpg':
      case 'jpeg':
        return ContentType('image', 'jpeg');
      case 'svg':
        return ContentType('image', 'svg+xml');
      case 'ico':
        return ContentType('image', 'x-icon');
      case 'wasm':
        return ContentType('application', 'wasm');
      case 'txt':
        return ContentType.text;
      default:
        return ContentType.binary;
    }
  }

  void _onSocket(WebSocket socket) {
    final client = Client(socket, 'Player');
    socket.listen(
      (raw) => _onMessage(client, raw),
      onDone: () => _onDisconnect(client),
      onError: (_) => _onDisconnect(client),
    );
  }

  void _onMessage(Client client, dynamic raw) {
    Map<String, dynamic> message;
    try {
      message = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      client.sendError('Bad message.');
      return;
    }

    try {
      switch (message['type']) {
        case 'register':
          _register(client, message);
          break;
        case 'login':
          _login(client, message);
          break;
        case 'leaderboard':
          _leaderboard(client);
          break;
        case 'wallet':
          _wallet(client);
          break;
        case 'ad_reward':
          _adReward(client, message);
          break;
        case 'join':
          _join(client, message);
          break;
        case 'cancel':
          _leaveQueue(client);
          break;
        case 'play':
          _play(client, message);
          break;
        case 'pass':
          _pass(client);
          break;
        case 'leave':
          _leaveRoom(client);
          break;
        default:
          client.sendError('Unknown message type.');
      }
    } catch (error) {
      client.sendError(error.toString());
    }
  }

  void _join(Client client, Map<String, dynamic> message) {
    if (client.inQueue || client.room != null) return;
    if (client.userId == null) {
      final raw = (message['name'] as String?)?.trim() ?? '';
      client.name =
          raw.isEmpty ? 'Player' : raw.substring(0, min(raw.length, 16));
    }
    client.inQueue = true;
    queue.add(client);
    _startMatchmakingClock();
    _notifyQueue();
  }

  void _startMatchmakingClock() {
    if (_matchmakingTimer != null) return;
    _matchDeadline = DateTime.now().add(const Duration(seconds: 20));
    _matchmakingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (queue.isEmpty) {
        timer.cancel();
        _matchmakingTimer = null;
        _matchDeadline = null;
        return;
      }

      final remaining = _matchDeadline!.difference(DateTime.now()).inSeconds;
      if (remaining <= 0) {
        timer.cancel();
        _matchmakingTimer = null;
        _matchDeadline = null;
        _startQueuedMatches();
      } else {
        _notifyQueue(remaining);
      }
    });
  }

  void _startQueuedMatches() {
    final waiting = queue.where((client) => client.alive).toList();
    queue.clear();
    while (waiting.isNotEmpty) {
      final seats = <Client?>[];
      for (var seat = 0; seat < kPlayersPerRoom; seat++) {
        final client = waiting.isEmpty ? null : waiting.removeAt(0);
        if (client != null) client.inQueue = false;
        seats.add(client);
      }

      final room = Room(_nextRoom++, seats);
      rooms.add(room);
      for (var seat = 0; seat < room.seats.length; seat++) {
        final client = room.seats[seat];
        if (client == null) continue;
        client.send({
          'type': 'start',
          'room': room.id,
          'seat': seat,
          'players': [
            for (var i = 0; i < room.seats.length; i++)
              {
                'name': room.seats[i]?.name ?? 'Bot ${i + 1}',
                'seat': i,
                'team': i % 2,
                'bot': room.seats[i] == null,
              },
          ],
        });
      }
      _publishRoom(room);
    }
    _notifyQueue(0);
  }

  void _notifyQueue([int? secondsRemaining]) {
    final remaining = secondsRemaining ??
        ((_matchDeadline?.difference(DateTime.now()).inMilliseconds ?? 20000) /
                1000)
            .ceil()
            .clamp(0, 20);
    for (var i = 0; i < queue.length; i++) {
      queue[i].send({
        'type': 'queued',
        'waiting': queue.length,
        'needed': kPlayersPerRoom,
        'position': i + 1,
        'secondsRemaining': remaining,
      });
    }
  }

  void _leaveQueue(Client client) {
    if (!client.inQueue) return;
    client.inQueue = false;
    queue.remove(client);
    if (queue.isEmpty) {
      _matchmakingTimer?.cancel();
      _matchmakingTimer = null;
      _matchDeadline = null;
    }
    _notifyQueue();
  }

  String _hashPassword(String password) {
    final bytes = utf8.encode('domino-salt:$password');
    return sha256.convert(bytes).toString();
  }

  String _generateToken() {
    return '${Random().nextInt(1 << 32).toRadixString(16)}'
        '${Random().nextInt(1 << 32).toRadixString(16)}';
  }

  void _register(Client client, Map<String, dynamic> message) {
    final username = (message['username'] as String?)?.trim() ?? '';
    final password = (message['password'] as String?) ?? '';
    if (username.length < 3 || username.length > 16) {
      throw 'Username must be 3-16 characters.';
    }
    if (password.length < 4) {
      throw 'Password must be at least 4 characters.';
    }
    final hash = _hashPassword(password);
    try {
      db.execute(
        'INSERT INTO users(username, password_hash, created_at) VALUES (?,?,?)',
        [username, hash, DateTime.now().toIso8601String()],
      );
    } catch (_) {
      throw 'Username already taken.';
    }
    final row = db.select('SELECT id FROM users WHERE username = ?', [username]).first;
    final userId = row['id'] as int;
    db.execute('INSERT OR IGNORE INTO stats(user_id) VALUES (?)', [userId]);
    db.execute('INSERT OR IGNORE INTO wallet(user_id) VALUES (?)', [userId]);
    client.userId = userId;
    client.name = username;
    client.token = _generateToken();
    client.send({
      'type': 'auth',
      'ok': true,
      'mode': 'register',
      'username': username,
      'token': client.token,
      'userId': userId,
    });
  }

  void _login(Client client, Map<String, dynamic> message) {
    final username = (message['username'] as String?)?.trim() ?? '';
    final password = (message['password'] as String?) ?? '';
    final rows = db.select(
      'SELECT id, password_hash FROM users WHERE username = ?',
      [username],
    );
    if (rows.isEmpty) throw 'Invalid credentials.';
    final row = rows.first;
    if (row['password_hash'] as String != _hashPassword(password)) {
      throw 'Invalid credentials.';
    }
    final userId = row['id'] as int;
    client.userId = userId;
    client.name = username;
    client.token = _generateToken();
    client.send({
      'type': 'auth',
      'ok': true,
      'mode': 'login',
      'username': username,
      'token': client.token,
      'userId': userId,
    });
  }

  void _leaderboard(Client client) {
    final rows = db.select('''
      SELECT u.username, s.wins, s.losses, s.total_score, s.games_played
      FROM stats s JOIN users u ON u.id = s.user_id
      ORDER BY s.total_score DESC, s.wins DESC
      LIMIT 20
    ''');
    client.send({
      'type': 'leaderboard',
      'entries': rows.map((r) => {
            'username': r['username'],
            'wins': r['wins'],
            'losses': r['losses'],
            'totalScore': r['total_score'],
            'gamesPlayed': r['games_played'],
          }).toList(),
    });
  }

  void _recordMatch(Room room) {
    if (room.matchRecorded) return;
    room.matchRecorded = true;
    final winner = room.winningTeam;
    if (winner == null) return;
    db.execute(
      'INSERT INTO matches(room_id, winner_team, scores, played_at) VALUES (?,?,?,?)',
      [room.id, winner, jsonEncode(room.scores), DateTime.now().toIso8601String()],
    );
    for (var seat = 0; seat < 4; seat++) {
      final client = room.seats[seat];
      if (client == null || client.userId == null) continue;
      final team = seat % 2;
      final won = team == winner;
      final points = room.scores[team];
      db.execute('''
        INSERT INTO stats(user_id, games_played, wins, losses, total_score)
        VALUES (?,?,?,?,?)
        ON CONFLICT(user_id) DO UPDATE SET
          games_played = games_played + 1,
          wins = wins + ?,
          losses = losses + ?,
          total_score = total_score + ?
      ''', [
        client.userId,
        1,
        won ? 1 : 0,
        won ? 0 : 1,
        points,
        won ? 1 : 0,
        won ? 0 : 1,
        points,
      ]);
    }
  }

  void _wallet(Client client) {
    if (client.userId == null) throw 'Login required.';
    final rows = db.select(
      'SELECT coins, gems FROM wallet WHERE user_id = ?',
      [client.userId],
    );
    int coins = 0;
    int gems = 0;
    if (rows.isNotEmpty) {
      coins = rows.first['coins'] as int;
      gems = rows.first['gems'] as int;
    } else {
      db.execute('INSERT OR IGNORE INTO wallet(user_id) VALUES (?)', [client.userId]);
    }
    client.send({'type': 'wallet', 'coins': coins, 'gems': gems});
  }

  void _adReward(Client client, Map<String, dynamic> message) {
    if (client.userId == null) throw 'Login required.';
    final type = (message['rewardType'] as String?) ?? 'coins';
    db.execute('INSERT OR IGNORE INTO wallet(user_id) VALUES (?)', [client.userId]);
    if (type == 'coins') {
      db.execute('UPDATE wallet SET coins = coins + 50 WHERE user_id = ?', [client.userId]);
    } else if (type == 'gems') {
      db.execute('UPDATE wallet SET gems = gems + 5 WHERE user_id = ?', [client.userId]);
    } else if (type == 'continue') {
      db.execute('UPDATE wallet SET coins = coins + 10 WHERE user_id = ?', [client.userId]);
    }
    _wallet(client);
  }

  void _play(Client client, Map<String, dynamic> message) {
    final room = client.room;
    if (room == null) throw 'You are not in a game.';
    final rawTile = message['tile'];
    if (rawTile is! List || rawTile.length != 2) throw 'Bad tile.';
    final tile = Tile(rawTile[0] as int, rawTile[1] as int);
    room.play(client.seat!, tile, (message['side'] as String?) ?? 'right');
    _publishRoom(room);
  }

  void _pass(Client client) {
    final room = client.room;
    if (room == null) throw 'You are not in a game.';
    room.pass(client.seat!);
    _publishRoom(room);
  }

  void _publishRoom(Room room) {
    if (room.status == 'gameover') _recordMatch(room);
    final type = room.status == 'gameover' ? 'gameover' : 'state';
    room.broadcast(type);
    _scheduleBotTurn(room);
  }

  void _scheduleBotTurn(Room room) {
    if (room.status != 'playing' || !room.isBotTurn) {
      _botTimers.remove(room)?.cancel();
      return;
    }
    if (_botTimers.containsKey(room)) return;

    _botTimers[room] = Timer(const Duration(milliseconds: 650), () {
      _botTimers.remove(room);
      if (!rooms.contains(room) ||
          room.status != 'playing' ||
          !room.isBotTurn) {
        return;
      }
      room.playBotTurn();
      _publishRoom(room);
    });
  }

  void _leaveRoom(Client client) {
    final room = client.room;
    if (room == null) return;
    client.room = null;
    _botTimers.remove(room)?.cancel();
    for (final other in room.seats) {
      if (other == null || other == client || !other.alive) continue;
      other.send({
        'type': 'gameover',
        'message': '${client.name} left the game.',
      });
      other.room = null;
    }
    rooms.remove(room);
  }

  void _onDisconnect(Client client) {
    _leaveQueue(client);
    _leaveRoom(client);
  }
}

Future<void> main(List<String> args) async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ??
      (args.isNotEmpty ? int.tryParse(args[0]) ?? 8080 : 8080);
  await Server().start(port);
}
