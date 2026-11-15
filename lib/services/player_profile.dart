import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One selectable avatar style: a gradient colour the player picks.
class AvatarStyle {
  final String label;
  final Color color;

  const AvatarStyle(this.label, this.color);
}

/// The eight avatars the player can choose from.
const List<AvatarStyle> kAvatars = [
  AvatarStyle('Aqua', Color(0xFF14B39B)),
  AvatarStyle('Gold', Color(0xFFF2A100)),
  AvatarStyle('Emerald', Color(0xFF1E9E3A)),
  AvatarStyle('Rose', Color(0xFFFF5FA2)),
  AvatarStyle('Azure', Color(0xFF2E94EA)),
  AvatarStyle('Ruby', Color(0xFFEF5350)),
  AvatarStyle('Amber', Color(0xFFF57C00)),
  AvatarStyle('Violet', Color(0xFF7E57C2)),
];

/// The player's local account: name, avatar, level and record. Stored with
/// shared_preferences so progress survives restarts on every platform.
class PlayerProfile extends ChangeNotifier {
  PlayerProfile._();

  static final PlayerProfile instance = PlayerProfile._();

  SharedPreferences? _prefs;

  static const _defaultName = 'PLAYER';

  static const _namePool = <String>[
    'NOVA',
    'RAVEN',
    'KAI',
    'LUNA',
    'ORION',
    'MILA',
    'ZEUS',
    'IRIS',
    'FELIX',
    'SAGE',
    'REX',
    'ACE',
    'NEO',
    'SKY',
    'BOLT',
    'DOM',
  ];

  /// Random one-time name for a brand-new profile, e.g. NOVA482.
  static String randomName() {
    final rng = Random();
    return '${_namePool[rng.nextInt(_namePool.length)]}'
        '${100 + rng.nextInt(900)}';
  }

  String name = _defaultName;
  int avatarIndex = 0;
  int level = 15;
  int xp = 1240;
  int coins = 1250;
  int gems = 112;
  int wins = 6;
  int losses = 2;
  int streak = 3;
  int bestStreak = 3;
  bool sound = true;
  bool music = true;
  bool vibration = true;
  bool hints = false;

  AvatarStyle get avatar => kAvatars[avatarIndex % kAvatars.length];

  String get initial =>
      name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

  int get xpGoal => 500 + level * 100;

  double get xpFraction => (xp / xpGoal).clamp(0.0, 1.0);

  String get formattedCoins {
    final s = coins.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }

  /// Reads the saved profile. Never throws; falls back to defaults.
  Future<void> load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (_) {
      return;
    }
    final p = _prefs!;
    final savedName = p.getString('profile.name');
    if (savedName == null || savedName.trim().isEmpty) {
      // First launch ever: give this profile its own random name once.
      name = randomName();
      unawaited(p.setString('profile.name', name));
    } else {
      name = savedName;
    }
    avatarIndex = p.getInt('profile.avatar') ?? avatarIndex;
    level = p.getInt('profile.level') ?? level;
    xp = p.getInt('profile.xp') ?? xp;
    coins = p.getInt('profile.coins') ?? coins;
    gems = p.getInt('profile.gems') ?? gems;
    wins = p.getInt('profile.wins') ?? wins;
    losses = p.getInt('profile.losses') ?? losses;
    streak = p.getInt('profile.streak') ?? streak;
    bestStreak = p.getInt('profile.bestStreak') ?? bestStreak;
    sound = p.getBool('profile.sound') ?? sound;
    music = p.getBool('profile.music') ?? music;
    vibration = p.getBool('profile.vibration') ?? vibration;
    hints = p.getBool('profile.hints') ?? hints;
    notifyListeners();
  }

  void _save() {
    final p = _prefs;
    if (p == null) return;
    unawaited(p.setString('profile.name', name));
    unawaited(p.setInt('profile.avatar', avatarIndex));
    unawaited(p.setInt('profile.level', level));
    unawaited(p.setInt('profile.xp', xp));
    unawaited(p.setInt('profile.coins', coins));
    unawaited(p.setInt('profile.gems', gems));
    unawaited(p.setInt('profile.wins', wins));
    unawaited(p.setInt('profile.losses', losses));
    unawaited(p.setInt('profile.streak', streak));
    unawaited(p.setInt('profile.bestStreak', bestStreak));
    unawaited(p.setBool('profile.sound', sound));
    unawaited(p.setBool('profile.music', music));
    unawaited(p.setBool('profile.vibration', vibration));
    unawaited(p.setBool('profile.hints', hints));
  }

  void _changed() {
    _save();
    notifyListeners();
  }

  void setName(String value) {
    final clean = value.trim();
    if (clean.isEmpty) return;
    name = clean.toUpperCase();
    _changed();
  }

  void setAvatar(int index) {
    avatarIndex = index % kAvatars.length;
    _changed();
  }

  void setSound(bool value) {
    sound = value;
    _changed();
  }

  void setMusic(bool value) {
    music = value;
    _changed();
  }

  void setVibration(bool value) {
    vibration = value;
    _changed();
  }

  void setHints(bool value) {
    hints = value;
    _changed();
  }

  void addCoins(int amount) {
    coins += amount;
    _changed();
  }

  void addGems(int amount) {
    gems += amount;
    _changed();
  }

  void setCoins(int value) {
    coins = value;
    _changed();
  }

  void setGems(int value) {
    gems = value;
    _changed();
  }

  void setWins(int value) {
    wins = value;
    _changed();
  }

  void setLosses(int value) {
    losses = value;
    _changed();
  }

  void addXp(int amount) {
    xp += amount;
    while (xp >= xpGoal) {
      xp -= xpGoal;
      level += 1;
    }
    _changed();
  }

  /// Credits one finished match (practice or online) to the account.
  void recordMatch({required bool win, int scoreXp = 0}) {
    if (win) {
      wins += 1;
      streak += 1;
      if (streak > bestStreak) bestStreak = streak;
      coins += 60;
      addXp(120 + scoreXp);
    } else {
      losses += 1;
      streak = 0;
      coins += 15;
      addXp(40 + scoreXp);
    }
  }

  void resetProgress() {
    level = 1;
    xp = 0;
    wins = 0;
    losses = 0;
    streak = 0;
    bestStreak = 0;
    _changed();
  }
}
