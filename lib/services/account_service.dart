import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'ad_service.dart';
import 'player_profile.dart';

class AccountService extends ChangeNotifier {
  AccountService._();
  static final AccountService instance = AccountService._();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;

  String get _host {
    final base = Uri.base.host;
    return base.isEmpty ? 'domino-server.taild9d968.ts.net' : base;
  }

  bool get isLocal =>
      _host == '127.0.0.1' || _host == 'localhost' || _host == '0.0.0.0';

  Uri get _uri {
    final scheme = isLocal ? 'ws' : 'wss';
    final port = isLocal ? 8080 : null;
    return Uri(scheme: scheme, host: _host, port: port);
  }

  int? userId;
  String? token;
  String? username;
  int coins = 0;
  int gems = 0;
  int gamesPlayed = 0;
  int wins = 0;
  int losses = 0;
  int totalScore = 0;
  bool sound = true;
  bool music = true;
  bool vibration = true;
  bool hints = false;
  bool connected = false;
  String? error;

  List<Map<String, dynamic>> leaderboard = [];
  List<Map<String, dynamic>> missions = [];
  List<Map<String, dynamic>> friends = [];

  /// When false, [connect] does nothing. Widget tests switch this off so the
  /// suite never opens a real socket (which leaves a pending connect timer).
  bool autoConnect = true;

  Future<void> connect() async {
    if (!autoConnect) return;
    if (_channel != null) return;
    try {
      final ch = WebSocketChannel.connect(_uri);
      _channel = ch;
      _subscription = ch.stream.listen(
        _onMessage,
        onError: (Object e) {
          error = '$e';
          notifyListeners();
        },
        onDone: () {
          connected = false;
          _channel = null;
          notifyListeners();
        },
      );
      await ch.ready;
      connected = true;
      notifyListeners();
    } catch (e) {
      error = '$e';
      notifyListeners();
    }
  }

  void _onMessage(dynamic raw) {
    Map<String, dynamic> m;
    try {
      m = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (m['type']) {
      case 'auth':
        if (m['ok'] == true) {
          userId = (m['userId'] as num?)?.toInt();
          token = m['token']?.toString();
          username = m['username']?.toString();
          error = null;
          requestWallet();
          requestSettings();
        } else {
          error = m['message']?.toString() ?? 'Auth failed';
        }
        break;
      case 'wallet':
        coins = (m['coins'] as num?)?.toInt() ?? coins;
        gems = (m['gems'] as num?)?.toInt() ?? gems;
        _syncProfile();
        break;
      case 'profile':
        username = m['username']?.toString() ?? username;
        gamesPlayed = (m['gamesPlayed'] as num?)?.toInt() ?? gamesPlayed;
        wins = (m['wins'] as num?)?.toInt() ?? wins;
        losses = (m['losses'] as num?)?.toInt() ?? losses;
        totalScore = (m['totalScore'] as num?)?.toInt() ?? totalScore;
        _syncProfile();
        break;
      case 'settings':
        sound = m['sound'] == true;
        music = m['music'] == true;
        vibration = m['vibration'] == true;
        hints = m['hints'] == true;
        final p = PlayerProfile.instance;
        p.setSound(sound);
        p.setMusic(music);
        p.setVibration(vibration);
        p.setHints(hints);
        break;
      case 'leaderboard':
        leaderboard = (m['entries'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        break;
      case 'missions':
        missions = (m['missions'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        break;
      case 'friends':
        friends = (m['friends'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        break;
      case 'error':
        error = m['message']?.toString();
        break;
    }
    notifyListeners();
  }

  void _syncProfile() {
    final p = PlayerProfile.instance;
    if (username != null) p.setName(username!);
    p.setCoins(coins);
    p.setGems(gems);
    p.setWins(wins);
    p.setLosses(losses);
  }

  void _send(Map<String, Object?> msg) {
    final ch = _channel;
    if (ch == null) return;
    try {
      ch.sink.add(jsonEncode(msg));
    } catch (_) {}
  }

  Future<void> register(String username, String password) async {
    await connect();
    _send({'type': 'register', 'username': username, 'password': password});
  }

  Future<void> login(String username, String password) async {
    await connect();
    _send({'type': 'login', 'username': username, 'password': password});
  }

  void logout() {
    userId = null;
    token = null;
    username = null;
    coins = 0;
    gems = 0;
    leaderboard = [];
    notifyListeners();
  }

  void requestWallet() => _send({'type': 'wallet'});

  void requestSettings() => _send({'type': 'settings_get'});

  void requestProfile() => _send({'type': 'profile_get'});

  void updateSettings({bool? sound, bool? music, bool? vibration, bool? hints}) {
    this.sound = sound ?? this.sound;
    this.music = music ?? this.music;
    this.vibration = vibration ?? this.vibration;
    this.hints = hints ?? this.hints;
    _send({
      'type': 'settings_set',
      'sound': this.sound,
      'music': this.music,
      'vibration': this.vibration,
      'hints': this.hints,
    });
    notifyListeners();
  }

  void requestLeaderboard() => _send({'type': 'leaderboard'});

  void _requestMissions() => requestMissions();
  void requestMissions() => _send({'type': 'missions_get'});

  void updateMission(String key, int progress) =>
      _send({'type': 'mission_update', 'key': key, 'progress': progress});

  void claimMission(String key) => _send({'type': 'mission_claim', 'key': key});

  void requestFriends() => _send({'type': 'friends_list'});

  void addFriend(String username) =>
      _send({'type': 'friend_add', 'username': username});

  void acceptFriend(int friendId) =>
      _send({'type': 'friend_accept', 'friendId': friendId});

  void removeFriend(int friendId) =>
      _send({'type': 'friend_remove', 'friendId': friendId});

  void inviteFriend(int friendId) =>
      _send({'type': 'invite_friend', 'friendId': friendId});

  Future<void> claimAdReward(String rewardType) async {
    final ok = await adService.showRewardedAd(rewardType: rewardType);
    if (!ok) return;
    _send({'type': 'ad_reward', 'rewardType': rewardType});
  }
}
