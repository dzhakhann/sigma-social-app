import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sigma_social_app/main.dart';

void main() {
  testWidgets('App boots to the Sigmacta splash', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const PulseApp());
    await tester.pump(); // render the first frame (splash)

    // The splash shows the Σ emblem and the wordmark. Matched as a SUBSTRING:
    // the wordmark reads "Sigmacta Systems", and asserting the exact string
    // 'Sigmacta' meant this test had been failing for a while unnoticed.
    expect(find.text('Σ'), findsWidgets);
    expect(find.textContaining('Sigmacta'), findsWidgets);

    // The splash schedules its navigation with Future.delayed; leaving those
    // timers pending fails the binding's end-of-test invariant check, so drain
    // them before the tree is torn down.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
  });
}
