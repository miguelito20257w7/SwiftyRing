import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:swiftyring/main.dart';

void main() {
  testWidgets('Muestra el formulario de login al arrancar', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: SwiftyRingApp()));

    expect(find.text('SwiftyRing'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'Iniciar sesión'), findsNothing);
    expect(find.text('Iniciar sesión'), findsOneWidget);
  });
}
