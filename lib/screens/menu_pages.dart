import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

class RanksPage extends StatelessWidget {
  const RanksPage({super.key});

  static List<List<Object>> _rows(PlayerProfile p) => [
        [1, 'NOVA', 'MASTER', 4820],
        [2, 'RAVEN', 'MASTER', 4610],
        [3, 'KAI', 'DIAMOND', 4390],
        [4, 'LUNA', 'DIAMOND', 4180],
        [5, 'ORION', 'DIAMOND', 4055],
        [6, 'MILA', 'PLATINUM', 3870],
        [7, 'ZEUS', 'PLATINUM', 3760],
        [8, 'IRIS', 'PLATINUM', 3620],
        [9, 'FELIX', 'GOLD', 3480],
        [10, 'SAGE', 'GOLD', 3355],
        [11, 'REX', 'GOLD', 3120],
        [12, p.name, 'GOLD', 1500 + p.wins * 120 - p.losses * 30],
      ];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PlayerProfile.instance,
      builder: (context, _) {
        final me = PlayerProfile.instance.name;
        final rows = _rows(PlayerProfile.instance);
        return MenuScaffold(
      title: 'RANKS',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _PageHeader(
            title: 'SEASON 1 LEADERBOARD',
            subtitle: 'Resets in 6 days · Top 3 promote',
          ),
          const SizedBox(height: 14),
          const MenuSectionLabel('LEADERBOARD'),
          MenuPanel(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(
              children: [
                for (final p in rows)
                  Builder(
                    builder: (context) {
                      final rank = p[0] as int;
                      final name = p[1] as String;
                      final tier = p[2] as String;
                      final points = p[3] as int;
                      final isMe = name == me;
                      final medal = rank == 1
                          ? MenuColors.gold
                          : rank == 2
                              ? const Color(0xFFC9D3DD)
                              : rank == 3
                                  ? const Color(0xFFD28B52)
                                  : MenuColors.frostEdge;
                      return _RowTile(
                        highlight: isMe ? MenuColors.goldDeep : null,
                        leading: SizedBox(
                          width: 30,
                          child: Text(
                            '#$rank',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: rank <= 3 ? medal : MenuColors.navy,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        title: name,
                        subtitle: tier,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$points',
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
                      );
                    },
                  ),
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

// ---------------------------------------------------------------------------
// Missions
// ---------------------------------------------------------------------------

class MissionsPage extends StatefulWidget {
  const MissionsPage({super.key});

  @override
  State<MissionsPage> createState() => _MissionsPageState();
}

class _MissionsPageState extends State<MissionsPage> {
  final _missions = <_Mission>[
    _Mission('Play 3 matches', 'Block, draw or fives', 3, 3, '250'),
    _Mission('Win 2 matches in a row', 'Any mode', 1, 2, '400'),
    _Mission('Play 5 doubles', 'Place a double in any match', 5, 5, '200'),
    _Mission('Score 100 points', 'Team score across matches', 72, 100, '350'),
    _Mission('Finish a hand without passing', 'No passes in one hand', 1, 1, '300'),
    _Mission('Invite a friend', 'Share your code once', 0, 1, '500'),
  ];

  void _claim(int index) {
    final m = _missions[index];
    if (!m.complete || m.claimed) return;
    setState(() => m.claimed = true);
    PlayerProfile.instance.addCoins(int.tryParse(m.reward) ?? 0);
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
  final String title;
  final String subtitle;
  final int target;
  int progress;
  final String reward;
  bool claimed = false;

  _Mission(
    this.title,
    this.subtitle,
    this.progress,
    this.target,
    this.reward,
  );

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
  final _friends = <_Friend>[
    _Friend('NOVA', 'Online · Gold III', _FriendState.online),
    _Friend('RAVEN', 'In a match', _FriendState.playing),
    _Friend('KAI', 'Online · Platinum I', _FriendState.online),
    _Friend('LUNA', 'Offline · 2h ago', _FriendState.offline),
    _Friend('ORION', 'Online · Silver II', _FriendState.online),
    _Friend('MILA', 'Offline · yesterday', _FriendState.offline),
  ];

  void _invite(_Friend f) {
    _toast(context, 'Invite sent to ${f.name}');
  }

  @override
  Widget build(BuildContext context) {
    final online = _friends.where((f) => f.state != _FriendState.offline).length;
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
                  onTap: () => _toast(context, 'Friend search is coming soon'),
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
              children: [for (final f in _friends) _friendRow(f)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _friendRow(_Friend f) {
    final color = switch (f.state) {
      _FriendState.online => MenuColors.greenDeep,
      _FriendState.playing => const Color(0xFFF57C00),
      _FriendState.offline => MenuColors.frostEdge,
    };
    final label = switch (f.state) {
      _FriendState.online => 'INVITE',
      _FriendState.playing => 'JOIN',
      _FriendState.offline => 'INVITE',
    };
    return _RowTile(
      leading: MenuAvatar(initial: f.name[0], color: color),
      title: f.name,
      subtitle: f.status,
      trailing: SizedBox(
        width: 68,
        child: MenuPressButton(
          onTap: () => _invite(f),
          height: 30,
          depth: 4,
          radius: 10,
          faceColors: f.state == _FriendState.offline
              ? const [Colors.white, MenuColors.frost]
              : const [MenuColors.green, MenuColors.greenDeep],
          edgeColor: f.state == _FriendState.offline
              ? MenuColors.frostEdge
              : MenuColors.greenEdge,
          child: Text(
            label,
            style: TextStyle(
              color: f.state == _FriendState.offline
                  ? MenuColors.navy
                  : Colors.white,
              fontSize: 9.5,
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
                    p.setSound),
                _toggle('Music', 'Menu and table soundtrack', p.music,
                    p.setMusic),
                _toggle('Vibration', 'Haptic feedback on plays', p.vibration,
                    p.setVibration),
                _toggle('Show hints', 'Highlight playable tiles', p.hints,
                    p.setHints),
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
                    MenuAvatar(
                      initial: p.initial,
                      color: p.avatar.color,
                      size: 64,
                      ring: true,
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
                            'GOLD III  ·  LEVEL ${p.level}',
                            style: TextStyle(
                              color: MenuColors.goldEdge,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 6),
                          MenuProgress(value: p.xpFraction, height: 8),
                          const SizedBox(height: 4),
                          Text(
                            '${p.xp} / ${p.xpGoal} XP',
                            style: TextStyle(
                              color: MenuColors.navy.withValues(alpha: 0.6),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
                    child: MenuAvatar(
                      initial: p.name.isEmpty ? '?' : p.name[0].toUpperCase(),
                      color: kAvatars[i].color,
                      size: 46,
                      ring: i == p.avatarIndex,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const MenuSectionLabel('STATS'),
          MenuPanel(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                _ProfileStat('${p.wins}', 'WINS', MenuColors.greenDeep),
                const _ProfileDivider(),
                _ProfileStat('${p.losses}', 'LOSSES', MenuColors.pink),
                const _ProfileDivider(),
                _ProfileStat(
                    '${p.bestStreak}', 'STREAK', const Color(0xFFF57C00)),
                const _ProfileDivider(),
                _ProfileStat('#${12 - p.wins.clamp(0, 11)}', 'RANK',
                    MenuColors.aquaDeep),
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

class _ProfileStat extends StatelessWidget {
  final String value;
  final String label;
  final Color color;

  const _ProfileStat(this.value, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: MenuColors.navy,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileDivider extends StatelessWidget {
  const _ProfileDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 34,
      color: MenuColors.navy.withValues(alpha: 0.1),
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
    return _RowTile(
      leading: Container(
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
      title: mode,
      subtitle: 'Ranked match',
      trailing: Text(
        points,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
