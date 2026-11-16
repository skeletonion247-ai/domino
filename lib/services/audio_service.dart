import 'package:audioplayers/audioplayers.dart';

import 'player_profile.dart';

class AudioService {
  AudioService._();
  static final AudioService instance = AudioService._();

  final AudioPlayer _music = AudioPlayer();
  final AudioPlayer _sfx = AudioPlayer();
  bool _musicStarted = false;

  Future<void> init() async {
    await _music.setReleaseMode(ReleaseMode.loop);
    await _music.setVolume(0.35);
    await _sfx.setVolume(0.8);
    if (PlayerProfile.instance.music) {
      await startMusic();
    }
  }

  Future<void> startMusic() async {
    if (_musicStarted) return;
    _musicStarted = true;
    try {
      await _music.play(AssetSource('audio/music_loop.wav'));
    } catch (_) {}
  }

  Future<void> stopMusic() async {
    _musicStarted = false;
    try {
      await _music.stop();
    } catch (_) {}
  }

  Future<void> setMusicEnabled(bool enabled) async {
    if (enabled) {
      await startMusic();
    } else {
      await stopMusic();
    }
  }

  Future<void> playClick() async {
    if (!PlayerProfile.instance.sound) return;
    try {
      await _sfx.play(AssetSource('audio/click.wav'));
    } catch (_) {}
  }

  Future<void> playWhoosh() async {
    if (!PlayerProfile.instance.sound) return;
    try {
      await _sfx.play(AssetSource('audio/whoosh.wav'));
    } catch (_) {}
  }

  Future<void> playTonk() async {
    if (!PlayerProfile.instance.sound) return;
    try {
      await _sfx.play(AssetSource('audio/tonk.wav'));
    } catch (_) {}
  }
}
