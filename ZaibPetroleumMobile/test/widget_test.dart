import 'package:flutter_test/flutter_test.dart';
import 'package:zaib_petroleum_mobile/main.dart';

void main() {
  testWidgets('App loads home brand', (WidgetTester tester) async {
    await tester.pumpWidget(const ZaibPetroleumApp());
    expect(find.textContaining('Zaib Petroleum'), findsWidgets);
  });
}
