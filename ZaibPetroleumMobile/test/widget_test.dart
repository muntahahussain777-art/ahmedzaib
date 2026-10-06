import 'package:flutter_test/flutter_test.dart';
import 'package:zaib_petroleum_mobile/main.dart';

void main() {
  testWidgets('App loads login brand', (WidgetTester tester) async {
    await tester.pumpWidget(const ZaibPetroleumApp());
    await tester.pump(); // first frame (LoginScreen)
    // App home is LoginScreen; brand is uppercase on that screen.
    expect(find.textContaining('ZAIB PETROLEUM'), findsWidgets);
  });
}
