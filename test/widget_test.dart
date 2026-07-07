import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sigma_social_app/main.dart';

void main() {
  testWidgets('App boots to the Sigmacta splash', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const PulseApp());
    await tester.pump(); // render the first frame (splash)

    // The splash shows the Σ emblem and the Sigmacta wordmark.
    expect(find.text('Σ'), findsWidgets);
    expect(find.text('Sigmacta'), findsWidgets);
  });
}
