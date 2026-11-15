import 'package:flutter_test/flutter_test.dart';
import 'package:domino/main.dart';
import 'package:domino/services/account_service.dart';

void main() {
  testWidgets('App loads', (WidgetTester tester) async {
    // The menu opens a socket on start; keep the test offline so no connect
    // timer is left pending when the tree is disposed.
    AccountService.instance.autoConnect = false;
    addTearDown(() => AccountService.instance.autoConnect = true);

    await tester.pumpWidget(const DominoApp());
    expect(find.textContaining('DOMINO'), findsWidgets);
    expect(find.text('PLAY'), findsOneWidget);
  });
}
