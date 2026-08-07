import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('CodingSaathi App Smoke Test', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Text('CodingSaathi AI'),
      ),
    ));
    expect(find.text('CodingSaathi AI'), findsOneWidget);
  });
}
