import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:domino/main.dart';
import 'package:domino/screens/menu_pages.dart';

void main() {
  testWidgets('every menu page renders without exceptions', (tester) async {
    final pages = <Widget>[
      const RanksPage(),
      const MissionsPage(),
      const FriendsPage(),
      const SettingsPage(),
      const ProfilePage(),
    ];
    for (final page in pages) {
      await tester.pumpWidget(MaterialApp(home: page));
      await tester.pump(const Duration(milliseconds: 120));
      expect(tester.takeException(), isNull, reason: '$page threw');
    }
  });

  testWidgets('nav buttons open their pages', (tester) async {
    final items = const [
      ['RANKS', 'SEASON 1 LEADERBOARD'],
      ['MISSIONS', 'DAILY MISSIONS'],
      ['FRIENDS', 'YOUR FRIENDS'],
      ['SETTINGS', 'AUDIO & FEEDBACK'],
    ];
    for (final item in items) {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(const DominoApp());
      await tester.pump(const Duration(milliseconds: 300));
      await tester.ensureVisible(find.text(item[0]));
      await tester.pump();
      await tester.tap(find.text(item[0]));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text(item[1]), findsOneWidget, reason: item[0]);
    }
  });
}
