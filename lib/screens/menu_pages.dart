import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/account_service.dart';
import '../services/audio_service.dart';
import '../services/player_profile.dart';
import '../widgets/menu_ui.dart';

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1100),
      ),
    );
}

class _PageHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _PageHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return MenuPanel(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          const Icon(
            Icons.auto_awesome_rounded,
            color: MenuColors.goldDeep,
            size: 28,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: MenuColors.navy,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: MenuColors.navy.withValues(alpha: 0.6),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
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

class _RowTile extends StatelessWidget {
  final Widget leading;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final Color? highlight;

  const _RowTile({
    required this.leading,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: highlight?.withValues(alpha: 0.10) ??
            Colors.white.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlight?.withValues(alpha: 0.8) ??
              MenuColors.frostEdge.withValues(alpha: 0.35),
          width: highlight != null ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MenuColors.navy,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: MenuColors.navy.withValues(alpha: 0.58),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ranks
// ---------------------------------------------------------------------------

class RanksPage extends StatefulWidget {
  const RanksPage({super.key});

  @override
  State<RanksPage> createState() => _RanksPageState();
}

class _RanksPageState extends State<RanksPage> {
  @override
  void initState() {
    super.initState();
    AccountService.instance.connect().then((_) {
      AccountService.instance.requestLeaderboard();
    });
    AccountService.instance.addListener(_onUpdate);
  }

  void _onUpdate() => setState(() {});

  @override
  void dispose() {
    AccountService.instance.removeListener(_onUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = AccountService.instance.leaderboard;
    return MenuScaffold(
      title: 'RANKS',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _PageHeader(
            title: 'SEASON 1 LEADERBOARD',
            subtitle: 'Live server rankings',
          ),
          const SizedBox(height: 14),
          const MenuSectionLabel('LEADERBOARD'),
          MenuPanel(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: entries.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Loading...', style: TextStyle(color: MenuColors.navy)),
                  )
                : Column(
                    children: [
                      for (var i = 0; i < entries.length; i++)
                        _RowTile(
                          leading: SizedBox(
                            width: 30,
                            child: Text(
                              '#${i + 1}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: MenuColors.navy,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          title: entries[i]['username']?.toString() ?? '',
                          subtitle: 'W ${entries[i]['wins']}  L ${entries[i]['losses']}',
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${entries[i]['totalScore']}',
                                style: const TextStyle(
                                  color: MenuColors.navy,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.star_rounded,
                                color: MenuColors.goldDeep,
                                size: 15,
                              ),
                            ],
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

// ---------------------------------------------------------------------------
// Missions
// ---------------------------------------------------------------------------

class MissionsPage extends StatefulWidget {
  const MissionsPage({super.key});

  @override
  State<MissionsPage> createState() => _MissionsPageState();
}

class _MissionsPageState extends State<MissionsPage> {
  final _missions = <_Mission>[];

  @override
  void initState() {
    super.initState();
    AccountService.instance.connect().then((_) {
      AccountService.instance.addListener(_onAccount);
      AccountService.instance.requestMissions();
    });
  }

  void _onAccount() {
    final ms = AccountService.instance.missions;
    if (ms.isEmpty) return;
    setState(() {
      _missions
        ..clear()
        ..addAll(ms.map((m) => _Mission(
              m['key']?.toString() ?? '',
              m['title']?.toString() ?? '',
              m['subtitle']?.toString() ?? '',
              (m['progress'] as num?)?.toInt() ?? 0,
              (m['target'] as num?)?.toInt() ?? 1,
              (m['reward'] as num?)?.toString() ?? '0',
              claimed: m['claimed'] == true,
            )));
    });
  }

  @override
  void dispose() {
    AccountService.instance.removeListener(_onAccount);
    super.dispose();
  }

  void _claim(int index) {
    final m = _missions[index];
    if (!m.complete || m.claimed) return;
    AccountService.instance.claimMission(_missions[index].key);
    setState(() => m.claimed = true);
    _toast(context, 'Claimed ${m.reward} coins');
  }

  @override
  Widget build(BuildContext context) {
    final done = _missions.where((m) => m.complete).length;
    return MenuScaffold(
      title: 'MISSIONS',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PageHeader(
            title: '$done OF ${_missions.length} COMPLETE',
            subtitle: 'Daily missions reset in 14 hours',
          ),
          const SizedBox(height: 14),
          const MenuSectionLabel('DAILY MISSIONS'),
          MenuPanel(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              children: [
                for (var i = 0; i < _missions.length; i++)
                  _missionRow(i, _missions[i]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _missionRow(int index, _Mission m) {
    final canClaim = m.complete && !m.claimed;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: MenuColors.frostEdge.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: m.complete
                        ? const [MenuColors.green, MenuColors.greenDeep]
                        : const [MenuColors.aqua, MenuColors.aquaDeep],
                  ),
                ),
                child: Icon(
                  m.complete
                      ? Icons.check_rounded
                      : Icons.flag_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: MenuColors.navy,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      m.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: MenuColors.navy.withValues(alpha: 0.55),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: MenuColors.gold.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: MenuColors.goldDeep.withValues(alpha: 0.45),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.monetization_on_rounded,
                      color: MenuColors.goldDeep,
                      size: 13,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      m.reward,
                      style: const TextStyle(
                        color: MenuColors.goldEdge,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: MenuProgress(
                  value: m.progress / m.target,
                  color: m.complete ? MenuColors.greenDeep : MenuColors.aquaDeep,
                  height: 7,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${m.progress}/${m.target}',
                style: TextStyle(
                  color: MenuColors.navy.withValues(alpha: 0.65),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (canClaim) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 64,
                  child: MenuPressButton(
                    onTap: () => _claim(index),
                    height: 30,
                    depth: 4,
                    radius: 10,
                    faceColors: const [MenuColors.green, MenuColors.greenDeep],
                    edgeColor: MenuColors.greenEdge,
                    child: const Text(
                      'CLAIM',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ] else if (m.claimed) ...[
                const SizedBox(width: 8),
                const Text(
                  'CLAIMED',
                  style: TextStyle(
                    color: MenuColors.greenDeep,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Mission {
  final String key;
  final String title;
  final String subtitle;
  final int target;
  int progress;
  final String reward;
  bool claimed = false;

  _Mission(
    this.key,
    this.title,
    this.subtitle,
    this.progress,
    this.target,
    this.reward, {
    this.claimed = false,
  });

  bool get complete => progress >= target;
}

// ---------------------------------------------------------------------------
// Friends
// ---------------------------------------------------------------------------

class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  @override
  void initState() {
    super.initState();
    AccountService.instance.connect().then((_) {
      AccountService.instance.requestFriends();
    });
    AccountService.instance.addListener(_onUpdate);
  }

  void _onUpdate() => setState(() {});

  @override
  void dispose() {
    AccountService.instance.removeListener(_onUpdate);
    super.dispose();
  }

  void _invite(String name) {
    _toast(context, 'Invite sent to $name');
  }

  void _addFriendDialog() {
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add friend'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'Username')),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              AccountService.instance.addFriend(ctrl.text.trim());
              Navigator.of(ctx).pop();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final friends = AccountService.instance.friends;
    final online = friends.length;
    return MenuScaffold(
      title: 'FRIENDS',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PageHeader(
            title: '$online FRIENDS ONLINE',
            subtitle: 'Invite code: D0M1N0 · tap to copy',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: MenuPressButton(
                  onTap: () {
                    Clipboard.setData(const ClipboardData(text: 'D0M1N0'));
                    _toast(context, 'Invite code copied');
                  },
                  height: 46,
                  depth: 5,
                  radius: 14,
                  faceColors: const [MenuColors.gold, MenuColors.goldDeep],
                  edgeColor: MenuColors.goldEdge,
                  child: const Text(
                    'COPY CODE',
                    style: TextStyle(
                      color: MenuColors.navy,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MenuPressButton(
                  onTap: _addFriendDialog,
                  height: 46,
                  depth: 5,
                  radius: 14,
                  faceColors: const [Colors.white, MenuColors.frost],
                  edgeColor: MenuColors.frostEdge,
                  child: const Text(
                    'ADD FRIEND',
                    style: TextStyle(
                      color: MenuColors.navy,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const MenuSectionLabel('YOUR FRIENDS'),
          MenuPanel(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(
              children: [for (final f in friends) _friendRow(f)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _friendRow(Map<String, dynamic> f) {
    final name = f['username']?.toString() ?? '';
    final status = f['status']?.toString() ?? '';
    final id = (f['id'] as num?)?.toInt() ?? 0;
    final accepted = status == 'accepted';
    return _RowTile(
      leading: MenuAvatar(initial: name.isEmpty ? '?' : name[0], color: MenuColors.aquaDeep),
      title: name,
      subtitle: status,
      trailing: SizedBox(
        width: 68,
        child: MenuPressButton(
          onTap: () {
            if (status == 'incoming') {
              AccountService.instance.acceptFriend(id);
            } else if (status == 'accepted') {
              AccountService.instance.inviteFriend(id);
              _toast(context, 'Invite sent to $name');
            } else {
              _toast(context, 'Pending request');
            }
          },
          height: 30,
          depth: 4,
          radius: 10,
          faceColors: accepted
              ? const [MenuColors.green, MenuColors.greenDeep]
              : const [Colors.white, MenuColors.frost],
          edgeColor: accepted ? MenuColors.greenEdge : MenuColors.frostEdge,
          child: Text(
            status == 'incoming' ? 'ACCEPT' : (accepted ? 'INVITE' : 'PENDING'),
            style: TextStyle(
              color: accepted ? Colors.white : MenuColors.navy,
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _Friend {
  final String name;
  final String status;
  final _FriendState state;

  _Friend(this.name, this.status, this.state);
}

enum _FriendState { online, playing, offline }

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  void initState() {
    super.initState();
    AccountService.instance.connect().then((_) {
      AccountService.instance.requestSettings();
    });
    AccountService.instance.addListener(_onUpdate);
  }

  void _onUpdate() => setState(() {});

  @override
  void dispose() {
    AccountService.instance.removeListener(_onUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PlayerProfile.instance,
      builder: (context, _) {
        final p = PlayerProfile.instance;
        return _settingsBody(p);
      },
    );
  }

  Widget _settingsBody(PlayerProfile p) {
    return MenuScaffold(
      title: 'SETTINGS',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _PageHeader(
            title: 'GAME SETTINGS',
            subtitle: 'Sound, feedback and table options',
          ),
          const SizedBox(height: 14),
          const MenuSectionLabel('AUDIO & FEEDBACK'),
          MenuPanel(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(
              children: [
                _toggle('Sound effects', 'Tiles, buttons and score', p.sound,
                    (v) { p.setSound(v); AccountService.instance.updateSettings(sound: v); }),
                _toggle('Music', 'Menu and table soundtrack', p.music,
                    (v) { p.setMusic(v); AccountService.instance.updateSettings(music: v); AudioService.instance.setMusicEnabled(v); }),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const MenuSectionLabel('DATA'),
          MenuPanel(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(
              children: [
                _RowTile(
                  leading: const Icon(
                    Icons.storage_rounded,
                    color: MenuColors.aquaDeep,
                    size: 26,
                  ),
                  title: 'Clear local data',
                  subtitle: 'Removes settings and cached sprites',
                  trailing: SizedBox(
                    width: 68,
                    child: MenuPressButton(
                      onTap: () => _toast(context, 'Cache cleared'),
                      height: 30,
                      depth: 4,
                      radius: 10,
                      faceColors: const [Colors.white, MenuColors.frost],
                      edgeColor: MenuColors.frostEdge,
                      child: const Text(
                        'CLEAR',
                        style: TextStyle(
                          color: MenuColors.navy,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
                _RowTile(
                  leading: const Icon(
                    Icons.restart_alt_rounded,
                    color: MenuColors.red,
                    size: 28,
                  ),
                  title: 'Reset progress',
                  subtitle: 'Clear wins, streak and missions',
                  trailing: SizedBox(
                    width: 68,
                    child: MenuPressButton(
                      onTap: _reset,
                      height: 30,
                      depth: 4,
                      radius: 10,
                      faceColors: const [Color(0xFFFF8A80), MenuColors.red],
                      edgeColor: const Color(0xFF8E1B1B),
                      child: const Text(
                        'RESET',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'DOMINO BATTLE ARENA  ·  v1.0',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggle(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: MenuColors.frostEdge.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: MenuColors.navy,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: MenuColors.navy.withValues(alpha: 0.55),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: MenuColors.greenDeep,
            activeThumbColor: Colors.white,
          ),
        ],
      ),
    );
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: const Text(
          'Reset progress?',
          style: TextStyle(
            color: MenuColors.navy,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: const Text(
          'Wins, streak and mission progress will be cleared.',
          style: TextStyle(color: MenuColors.navy),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'RESET',
              style: TextStyle(color: MenuColors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      _toast(context, 'Progress reset');
    }
  }
}


// ---------------------------------------------------------------------------
// Profile
// ---------------------------------------------------------------------------

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  @override
  void initState() {
    super.initState();
    AccountService.instance.connect().then((_) {
      AccountService.instance.requestProfile();
    });
    AccountService.instance.addListener(_onUpdate);
  }

  void _onUpdate() => setState(() {});

  @override
  void dispose() {
    AccountService.instance.removeListener(_onUpdate);
    super.dispose();
  }

  Future<void> _showProfileAccountDialog(BuildContext context) async {
    final userCtrl = TextEditingController(text: AccountService.instance.username ?? '');
    final passCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: userCtrl, decoration: const InputDecoration(labelText: 'Username')),
            TextField(controller: passCtrl, decoration: const InputDecoration(labelText: 'Password'), obscureText: true),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => AccountService.instance.login(userCtrl.text.trim(), passCtrl.text),
                    child: const Text('Login'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => AccountService.instance.register(userCtrl.text.trim(), passCtrl.text),
                    child: const Text('Register'),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              AccountService.instance.logout();
              Navigator.of(ctx).pop();
            },
            child: const Text('Logout'),
          ),
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
        ],
      ),
    );
    userCtrl.dispose();
    passCtrl.dispose();
  }

  Future<void> _editName() async {
    final controller = TextEditingController(
      text: PlayerProfile.instance.name,
    );
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: const Text(
          'Edit name',
          style: TextStyle(
            color: MenuColors.navy,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 12,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            hintText: 'Your name',
            counterText: '',
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && mounted) {
      PlayerProfile.instance.setName(name);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PlayerProfile.instance,
      builder: (context, _) {
        final p = PlayerProfile.instance;
        return MenuScaffold(
      title: 'PROFILE',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MenuPanel(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              children: [
                Row(
                  children: [
                    _LevelAvatar(
                      initial: p.initial,
                      color: p.avatar.color,
                      level: p.level,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: MenuColors.navy,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${p.wins} WINS  ·  ${p.losses} LOSSES',
                            style: TextStyle(
                              color: MenuColors.goldEdge,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text(
                      'LEVEL ${p.level}',
                      style: const TextStyle(
                        color: MenuColors.navy,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${p.xp} / ${p.xpGoal} XP',
                      style: const TextStyle(
                        color: MenuColors.goldEdge,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                MenuProgress(
                  value: p.xpFraction,
                  color: MenuColors.aquaDeep,
                  height: 10,
                ),
                const SizedBox(height: 14),
                MenuPressButton(
                  onTap: _editName,
                  height: 40,
                  depth: 5,
                  radius: 13,
                  faceColors: const [MenuColors.gold, MenuColors.goldDeep],
                  edgeColor: MenuColors.goldEdge,
                  child: const Text(
                    'EDIT NAME',
                    style: TextStyle(
                      color: MenuColors.navy,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const MenuSectionLabel('AVATAR'),
          MenuPanel(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                for (var i = 0; i < kAvatars.length; i++)
                  GestureDetector(
                    onTap: () => p.setAvatar(i),
                    child: _AvatarChoice(
                      initial: p.name.isEmpty ? '?' : p.name[0].toUpperCase(),
                      color: kAvatars[i].color,
                      selected: i == p.avatarIndex,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const MenuSectionLabel('ACCOUNT'),
          MenuPanel(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              children: [
                ListenableBuilder(
                  listenable: AccountService.instance,
                  builder: (_, __) {
                    final a = AccountService.instance;
                    return Text(
                      a.username == null
                          ? 'Not logged in'
                          : 'Logged in as ${a.username}  •  ${a.coins} coins  ${a.gems} gems',
                      style: const TextStyle(
                        color: MenuColors.navy,
                        fontWeight: FontWeight.w700,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: MenuPressButton(
                        onTap: () => _showProfileAccountDialog(context),
                        height: 42,
                        depth: 5,
                        radius: 13,
                        faceColors: const [
                          MenuColors.skyTop,
                          MenuColors.skyMid,
                        ],
                        edgeColor: MenuColors.skyDeep,
                        child: const Text(
                          'LOGIN / REGISTER',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: MenuPressButton(
                        onTap: () =>
                            AccountService.instance.claimAdReward('coins'),
                        height: 42,
                        depth: 5,
                        radius: 13,
                        faceColors: const [
                          MenuColors.green,
                          MenuColors.greenDeep,
                        ],
                        edgeColor: MenuColors.greenEdge,
                        child: const Text(
                          'AD +50 COINS',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const MenuSectionLabel('STATS'),
          MenuPanel(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(
                  child: _ProfileStatTile(
                    '${p.wins}',
                    'WINS',
                    MenuColors.greenDeep,
                    Icons.emoji_events_rounded,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ProfileStatTile(
                    '${p.losses}',
                    'LOSSES',
                    MenuColors.pink,
                    Icons.close_rounded,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ProfileStatTile(
                    '${p.bestStreak}',
                    'STREAK',
                    const Color(0xFFF57C00),
                    Icons.local_fire_department_rounded,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ProfileStatTile(
                    '#${12 - p.wins.clamp(0, 11)}',
                    'RANK',
                    MenuColors.aquaDeep,
                    Icons.military_tech_rounded,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const MenuSectionLabel('RECENT MATCHES'),
          MenuPanel(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(
              children: const [
                _MatchRow('WIN', '2v2 · Block', '+120', MenuColors.greenDeep),
                _MatchRow('WIN', '1v1 · Draw', '+90', MenuColors.greenDeep),
                _MatchRow('LOSS', '2v2 · Fives', '-45', MenuColors.pink),
                _MatchRow('WIN', '2v2 · Block', '+110', MenuColors.greenDeep),
              ],
            ),
          ),
        ],
      ),
    );
      },
    );
  }
}

class _ProfileStatTile extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final IconData icon;

  const _ProfileStatTile(this.value, this.label, this.color, this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Color(0xFFEAF5FF)],
        ),
        border: Border.all(color: Colors.white, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: MenuColors.navy.withValues(alpha: 0.18),
            blurRadius: 6,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: MenuColors.navy,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 8,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _MatchRow extends StatelessWidget {
  final String result;
  final String mode;
  final String points;
  final Color color;

  const _MatchRow(this.result, this.mode, this.points, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Color(0xFFEAF5FF)],
        ),
        border: Border.all(color: Colors.white, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: MenuColors.navy.withValues(alpha: 0.16),
            blurRadius: 6,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: color.withValues(alpha: 0.5)),
            ),
            child: Center(
              child: Text(
                result,
                style: TextStyle(
                  color: color,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mode,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MenuColors.navy,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'Ranked match',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: MenuColors.navy.withValues(alpha: 0.58),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            points,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

/// Profile avatar with a raised gold ring and the level badge on its corner.
class _LevelAvatar extends StatelessWidget {
  final String initial;
  final Color color;
  final int level;

  const _LevelAvatar({
    required this.initial,
    required this.color,
    required this.level,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 72,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            right: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [MenuColors.gold, MenuColors.goldDeep],
                ),
                boxShadow: [
                  BoxShadow(
                    color: MenuColors.goldEdge.withValues(alpha: 0.55),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: MenuAvatar(
                initial: initial,
                color: color,
                size: 54,
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: MenuColors.navy,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: MenuColors.gold, width: 1.6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                '$level',
                style: const TextStyle(
                  color: MenuColors.gold,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  height: 1.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Avatar choice in the picker: the selected one sits raised on a gold base.
class _AvatarChoice extends StatelessWidget {
  final String initial;
  final Color color;
  final bool selected;

  const _AvatarChoice({
    required this.initial,
    required this.color,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      transform: Matrix4.translationValues(0, selected ? -3 : 0, 0),
      padding: EdgeInsets.all(selected ? 4 : 3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: selected
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [MenuColors.gold, MenuColors.goldDeep],
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: MenuColors.navy.withValues(alpha: selected ? 0.32 : 0.16),
            blurRadius: selected ? 8 : 5,
            offset: Offset(0, selected ? 4 : 2),
          ),
        ],
      ),
      child: MenuAvatar(initial: initial, color: color, size: 42),
    );
  }
}
