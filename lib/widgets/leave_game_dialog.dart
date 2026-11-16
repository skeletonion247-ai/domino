import 'package:flutter/material.dart';

import '../theme/arcade_ui.dart';

/// Leave/quit confirmation styled like the rest of the arcade UI.
///
/// Returns 'menu' (keep the game, go back), 'quit' (end the game) or 'stay'.
Future<String?> showLeaveGameDialog(
  BuildContext context, {
  required bool online,
}) {
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: _LeaveCard(online: online),
      ),
    ),
  );
}

class _LeaveCard extends StatelessWidget {
  final bool online;

  const _LeaveCard({required this.online});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Raised lower edge, so the card sits on the table like the buttons.
        Positioned.fill(
          top: 9,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [ArcadeColors.navy, ArcadeColors.navyDeep],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white, Color(0xFFEAF5FF)],
            ),
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      ArcadeColors.skyTop,
                      ArcadeColors.skyMid,
                      ArcadeColors.skyDeep,
                    ],
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.55),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: ArcadeColors.navyDeep.withValues(alpha: 0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: const Text(
                  'LEAVE THE TABLE?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.6,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                online
                    ? 'Back to menu keeps the game running and you can '
                          'rejoin from online. Quit gives your seat to a bot.'
                    : 'Back to menu keeps this game so you can continue it '
                          'later. Quit ends it.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: ArcadeColors.navy.withValues(alpha: 0.75),
                  fontSize: 12.5,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ArcadeButton(
                  onTap: () => Navigator.pop(context, 'menu'),
                  height: 44,
                  depth: 5,
                  radius: 14,
                  faceColors: const [
                    ArcadeColors.gold,
                    ArcadeColors.goldDeep,
                  ],
                  edgeColor: ArcadeColors.goldEdge,
                  child: const Text(
                    'BACK TO MENU',
                    style: TextStyle(
                      color: ArcadeColors.navy,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 9),
              SizedBox(
                width: double.infinity,
                child: ArcadeButton(
                  onTap: () => Navigator.pop(context, 'quit'),
                  height: 44,
                  depth: 5,
                  radius: 14,
                  faceColors: const [
                    Color(0xFFFF8A80),
                    Color(0xFFD32F2F),
                  ],
                  edgeColor: const Color(0xFF8E0000),
                  child: const Text(
                    'QUIT GAME',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 9),
              SizedBox(
                width: double.infinity,
                child: ArcadeButton(
                  onTap: () => Navigator.pop(context, 'stay'),
                  height: 42,
                  depth: 5,
                  radius: 14,
                  faceColors: const [Colors.white, ArcadeColors.frost],
                  edgeColor: ArcadeColors.frostEdge,
                  child: const Text(
                    'STAY',
                    style: TextStyle(
                      color: ArcadeColors.navy,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
