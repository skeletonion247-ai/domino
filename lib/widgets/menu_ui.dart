import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/domino_tile.dart';
import '../services/audio_service.dart';
import 'sprite_domino_tile.dart';

/// Colours shared by the main menu and every sub-page so the look stays
/// consistent.
class MenuColors {
  static const skyTop = Color(0xFF7AD7FF);
  static const skyMid = Color(0xFF2E94EA);
  static const skyDeep = Color(0xFF1456B8);
  static const aqua = Color(0xFF45F0D2);
  static const aquaDeep = Color(0xFF14B39B);
  static const gold = Color(0xFFFFD84D);
  static const goldDeep = Color(0xFFF2A100);
  static const goldEdge = Color(0xFF8A4A00);
  static const green = Color(0xFF6BE46F);
  static const greenDeep = Color(0xFF1E9E3A);
  static const greenEdge = Color(0xFF0B6320);
  static const navy = Color(0xFF0B2A5B);
  static const navyDeep = Color(0xFF071C3F);
  static const pink = Color(0xFFFF5FA2);
  static const frost = Color(0xFFD9EEFF);
  static const frostEdge = Color(0xFF6E9FCF);
  static const red = Color(0xFFEF5350);
}

/// Animated sky backdrop with drifting bubbles and floating tiles.
class MenuBackdrop extends StatefulWidget {
  const MenuBackdrop({super.key});

  @override
  State<MenuBackdrop> createState() => _MenuBackdropState();
}

class _MenuBackdropState extends State<MenuBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _float;

  @override
  void initState() {
    super.initState();
    _float = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _float,
      builder: (context, _) => _build(_float.value),
    );
  }

  Widget _build(double t) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                MenuColors.skyTop,
                MenuColors.skyMid,
                MenuColors.skyDeep,
              ],
              stops: [0.0, 0.55, 1.0],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.9),
              radius: 0.9,
              colors: [Color(0x55FFFFFF), Color(0x00FFFFFF)],
            ),
          ),
        ),
        CustomPaint(painter: _MenuBubblePainter(t: t)),
        _drift(const DominoTile(6, 6), const Alignment(-0.95, -0.55), 0.6, -0.4, 0.0, t),
        _drift(const DominoTile(5, 2), const Alignment(0.95, -0.25), 0.55, 0.35, 0.4, t),
        _drift(const DominoTile(3, 1), const Alignment(-0.9, 0.7), 0.5, 0.3, 0.7, t),
        _drift(const DominoTile(4, 4), const Alignment(0.92, 0.75), 0.55, -0.3, 0.2, t),
      ],
    );
  }

  Widget _drift(
    DominoTile tile,
    Alignment at,
    double scale,
    double angle,
    double phase,
    double t,
  ) {
    final wave = math.sin((t + phase) * 2 * math.pi);
    return Align(
      alignment: at,
      child: Transform.translate(
        offset: Offset(0, wave * 12),
        child: Transform.rotate(
          angle: angle + wave * 0.05,
          child: Opacity(
            opacity: 0.5,
            child: SpriteDominoTile(tile: tile, scale: scale),
          ),
        ),
      ),
    );
  }
}

class _MenuBubblePainter extends CustomPainter {
  final double t;

  const _MenuBubblePainter({required this.t});

  static const _seeds = <List<double>>[
    [0.12, 0.10, 22, 0.15],
    [0.80, 0.08, 16, 0.10],
    [0.45, 0.22, 30, 0.12],
    [0.90, 0.36, 12, 0.18],
    [0.08, 0.42, 26, 0.10],
    [0.62, 0.52, 14, 0.14],
    [0.30, 0.66, 34, 0.09],
    [0.86, 0.72, 20, 0.12],
    [0.18, 0.90, 18, 0.15],
    [0.55, 0.92, 28, 0.10],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint();
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (var i = 0; i < _seeds.length; i++) {
      final s = _seeds[i];
      final drift = (t * (0.4 + (i % 3) * 0.2) + s[1]) % 1.0;
      final center = Offset(
        s[0] * size.width + math.sin((t + i) * math.pi) * 10,
        (1 - drift) * size.height,
      );
      final r = s[2];
      fill.color = Colors.white.withValues(alpha: s[3]);
      ring.color = Colors.white.withValues(alpha: s[3] + 0.12);
      canvas.drawCircle(center, r, fill);
      canvas.drawCircle(center, r, ring);
    }
  }

  @override
  bool shouldRepaint(covariant _MenuBubblePainter oldDelegate) =>
      oldDelegate.t != t;
}

/// Standard sub-page: same sky backdrop as the menu, a back button, a title
/// pill, and a scrollable body.
class MenuScaffold extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const MenuScaffold({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: MenuBackdrop()),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                      child: Row(
                        children: [
                          MenuPressButton(
                            onTap: () => Navigator.of(context).maybePop(),
                            height: 46,
                            depth: 5,
                            radius: 15,
                            width: 46,
                            faceColors: const [Colors.white, MenuColors.frost],
                            edgeColor: MenuColors.frostEdge,
                            child: const Icon(
                              Icons.arrow_back_rounded,
                              color: MenuColors.navy,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Container(
                              height: 46,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: MenuColors.navy,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: MenuColors.navyDeep.withValues(
                                      alpha: 0.45,
                                    ),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Text(
                                title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 3,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 46,
                            height: 51,
                            child: trailing,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        child: child,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// White rounded panel with a soft navy shadow (same as the main menu).
class MenuPanel extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  const MenuPanel({
    super.key,
    required this.child,
    this.radius = 18,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: MenuColors.navy.withValues(alpha: 0.22),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Color(0xFFEAF5FF)],
          ),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: child,
      ),
    );
  }
}

/// Chunky 3D button with a lower edge that sinks when pressed.
class MenuPressButton extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget child;
  final List<Color> faceColors;
  final Color edgeColor;
  final double height;
  final double depth;
  final double radius;
  final double? width;

  const MenuPressButton({
    super.key,
    required this.onTap,
    required this.child,
    required this.faceColors,
    required this.edgeColor,
    this.height = 52,
    this.depth = 6,
    this.radius = 16,
    this.width,
  });

  @override
  State<MenuPressButton> createState() => _MenuPressButtonState();
}

class _MenuPressButtonState extends State<MenuPressButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final h = widget.height;
    final d = widget.depth;
    final radius = BorderRadius.circular(widget.radius);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap == null
          ? null
          : () {
              AudioService.instance.playClick();
              widget.onTap!();
            },
      child: SizedBox(
        height: h + d,
        width: widget.width,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: h,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.edgeColor,
                  borderRadius: radius,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 90),
              curve: Curves.easeOut,
              left: 0,
              right: 0,
              top: _down ? d : 0,
              height: h,
              child: ClipRRect(
                borderRadius: radius,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: widget.faceColors,
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.topCenter,
                      child: FractionallySizedBox(
                        heightFactor: 0.5,
                        widthFactor: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.white.withValues(alpha: 0.35),
                                Colors.white.withValues(alpha: 0.0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Center(child: widget.child),
                    IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: radius,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.45),
                            width: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small white uppercase section label used between panels.
class MenuSectionLabel extends StatelessWidget {
  final String text;

  const MenuSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 2, 6, 8),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.92),
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 2,
          shadows: [
            Shadow(
              color: MenuColors.navyDeep.withValues(alpha: 0.45),
              blurRadius: 4,
            ),
          ],
        ),
      ),
    );
  }
}

/// Round avatar with an initial, matching the menu's profile badge.
class MenuAvatar extends StatelessWidget {
  final String initial;
  final Color color;
  final double size;
  final bool ring;

  const MenuAvatar({
    super.key,
    required this.initial,
    this.color = MenuColors.aquaDeep,
    this.size = 42,
    this.ring = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(color, Colors.white, 0.35)!,
            color,
            Color.lerp(color, Colors.black, 0.3)!,
          ],
        ),
        border: Border.all(
          color: ring ? MenuColors.gold : Colors.white,
          width: ring ? 2.5 : 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: size * 0.36,
          ),
        ),
      ),
    );
  }
}

/// Slim progress bar used on missions and the profile page.
class MenuProgress extends StatelessWidget {
  final double value;
  final Color color;
  final double height;

  const MenuProgress({
    super.key,
    required this.value,
    this.color = MenuColors.aquaDeep,
    this.height = 8,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Container(
        height: height,
        color: MenuColors.navy.withValues(alpha: 0.12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: value.clamp(0.0, 1.0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color.lerp(color, Colors.white, 0.25)!, color],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
