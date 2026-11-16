import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/arcade_ui.dart';

/// Radial emote menu that pops out of [origin] (your avatar).
/// Returns 'brick' or null.
Future<String?> showEmoteWheel(
  BuildContext context, {
  required Offset origin,
}) {
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.28),
    builder: (_) => _EmoteWheel(origin: origin),
  );
}

class _Emote {
  final String id;
  final String label;
  final Widget icon;

  const _Emote(this.id, this.label, this.icon);
}

class _EmoteWheel extends StatefulWidget {
  final Offset origin;

  const _EmoteWheel({required this.origin});

  @override
  State<_EmoteWheel> createState() => _EmoteWheelState();
}

class _EmoteWheelState extends State<_EmoteWheel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  )..forward();

  static const _emotes = <_Emote>[
    _Emote('brick', 'BRICK', BrickView(width: 30)),
    _Emote(
      'laugh',
      'LAUGH',
      Icon(
        Icons.sentiment_very_satisfied_rounded,
        size: 30,
        color: Color(0xFFF2A100),
      ),
    ),
    _Emote(
      'gg',
      'GG',
      Icon(Icons.thumb_up_rounded, size: 28, color: Color(0xFF2E94EA)),
    ),
  ];

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = _emotes.length;
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          for (var i = 0; i < n; i++) _button(_emotes[i], i, n),
        ],
      ),
    );
  }

  Widget _button(_Emote emote, int i, int n) {
    // Arc opening up-right from the avatar.
    final angle = n == 1
        ? -0.62
        : -1.0 + 1.35 * i / (n - 1);
    final target =
        widget.origin + Offset(math.cos(angle), math.sin(angle)) * 96;

    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeOutBack.transform(
          ((_c.value - i * 0.1) / 0.8).clamp(0.0, 1.0),
        );
        final p = t.clamp(0.0, 1.0);
        final pos = Offset.lerp(widget.origin, target, p)!;
        final screen = MediaQuery.sizeOf(context);
        final left = (pos.dx - 38)
            .clamp(0.0, math.max(0.0, screen.width - 76))
            .toDouble();
        final top = (pos.dy - 30)
            .clamp(0.0, math.max(0.0, screen.height - 92))
            .toDouble();
        return Positioned(
          left: left,
          top: top,
          width: 76,
          height: 92,
          child: Opacity(
            opacity: p,
            child: Transform.scale(
              scale: 0.35 + 0.65 * t,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.pop(context, emote.id),
                child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.white, Color(0xFFEAF5FF)],
                        ),
                        border: Border.all(
                          color: ArcadeColors.gold,
                          width: 2.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                          BoxShadow(
                            color: ArcadeColors.gold.withValues(alpha: 0.35),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: Center(child: emote.icon),
                    ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: ArcadeColors.navy.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      emote.label,
                      style: const TextStyle(
                        color: ArcadeColors.gold,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Small brick, used in the menu and in flight.
class BrickView extends StatelessWidget {
  final double width;

  const BrickView({super.key, required this.width});

  @override
  Widget build(BuildContext context) {
    final h = width * 0.5;
    return Container(
      width: width,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(width * 0.10),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE07A5F), Color(0xFFB24A32), Color(0xFF7E2F1F)],
        ),
        border: Border.all(color: const Color(0xFF5A2015), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(height: h * 0.32),
          Container(height: 1.4, color: const Color(0x55FFF0E8)),
          SizedBox(height: h * 0.28),
          Container(height: 1.4, color: const Color(0x55FFF0E8)),
        ],
      ),
    );
  }
}
