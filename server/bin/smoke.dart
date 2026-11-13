import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Joins one player, verifies the 20-second bot-fill match, and plays through a
/// a complete hand against the three server-controlled bots.
/// Usage: dart run bin/smoke.dart [ws://127.0.0.1:8080]
Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args[0] : 'ws://127.0.0.1:8080';
  final clients = <_Fake>[];
  var finished = false;

  Future<void> done(String reason) async {
    if (finished) return;
    finished = true;
    stdout.writeln('DONE: $reason');
    for (final c in clients) {
      await c.socket.close();
    }
    exit(0);
  }

  final socket = await WebSocket.connect(url);
  final fake = _Fake(socket, 'SmokePlayer', done);
  clients.add(fake);
  socket.listen(fake.onData, onDone: () {}, onError: (_) {});
  socket.add(jsonEncode({'type': 'join', 'name': 'SmokePlayer'}));

  Timer(const Duration(seconds: 60), () {
    done('timeout — no hand completed within 60s');
  });
}

class _Fake {
  final WebSocket socket;
  final String name;
  final void Function(String) onDone;
  final Random random = Random();
  int? seat;
  int actions = 0;
  int states = 0;

  _Fake(this.socket, this.name, this.onDone);

  void onData(dynamic raw) {
    final message = jsonDecode(raw as String) as Map<String, dynamic>;
    switch (message['type']) {
      case 'start':
        seat = message['seat'] as int;
        stdout.writeln('Started in seat ${seat! + 1}: ${message['players']}');
        final players = message['players'] as List;
        final botCount = players.where((p) => (p as Map)['bot'] == true).length;
        if (botCount != 3) {
          stderr.writeln('Expected three bots, got $botCount');
          exit(1);
        }
        break;
      case 'queued':
        stdout.writeln('Queued: ${message['secondsRemaining']}s remaining');
        break;
      case 'state':
        states++;
        if (states % 10 == 0) {
          stdout.writeln(
            'State $states: turn ${message['turn']}, '
            'score ${message['scores']}, board ${(message['board'] as List).length}',
          );
        }
        _maybeAct(message);
        break;
      case 'gameover':
        onDone('game over');
        break;
      case 'error':
        stderr.writeln('$name error: ${message['message']}');
        exit(1);
    }
  }

  void _maybeAct(Map<String, dynamic> state) {
    if (state['status'] != 'playing') {
      onDone('game over');
      return;
    }
    final board = state['board'] as List;
    final scores = (state['scores'] as List).cast<int>();
    if (board.isEmpty && scores.any((score) => score > 0)) {
      onDone('completed a hand with scores $scores');
      return;
    }
    if (state['turn'] != seat) return;
    if (seat == null) return;

    final hand =
        (state['hand'] as List).map((t) => (t as List).cast<int>()).toList();
    final left = state['left'] as int;
    final right = state['right'] as int;
    final empty = state['board'] is List && (state['board'] as List).isEmpty;

    final moves = <List<int>>[];
    for (final tile in hand) {
      if (empty ||
          tile[0] == left ||
          tile[1] == left ||
          tile[0] == right ||
          tile[1] == right) {
        moves.add(tile);
      }
    }

    if (moves.isEmpty) {
      socket.add(jsonEncode({'type': 'pass'}));
      return;
    }

    final tile = moves[random.nextInt(moves.length)];
    String side = 'right';
    if (!empty) {
      final fitsLeft = tile[0] == left || tile[1] == left;
      final fitsRight = tile[0] == right || tile[1] == right;
      if (fitsLeft && !fitsRight) side = 'left';
      if (fitsLeft && fitsRight) side = random.nextBool() ? 'left' : 'right';
    }
    actions++;
    if (actions % 10 == 0) stdout.writeln('Human actions: $actions');
    if (actions > 500) {
      stderr.writeln('$name: too many actions');
      exit(1);
    }
    socket.add(jsonEncode({
      'type': 'play',
      'tile': tile,
      'side': side,
    }));
  }
}
