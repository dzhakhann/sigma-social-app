import 'package:flutter_test/flutter_test.dart';
import 'package:sigma_social_app/main.dart';

void main() {
  testWidgets('App starts', (WidgetTester tester) async {
    await tester.pumpWidget(const SigmaSocialApp());
    expect(find.text('SIGMA'), findsOneWidget);
  });
}
