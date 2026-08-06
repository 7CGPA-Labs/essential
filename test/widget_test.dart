import 'package:flutter_test/flutter_test.dart';
import 'package:codingsaathi/main.dart';

void main() {
  testWidgets('CodingSaathi App Smoke Test', (WidgetTester tester) async {
    await tester.pumpWidget(const CodingSaathiApp());
    expect(find.text('CodingSaathi AI'), findsOneWidget);
  });
}
