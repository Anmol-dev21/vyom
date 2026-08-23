import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vyom_business/features/onboarding/language_selection_screen.dart';

void main() {
  testWidgets('shows language selection options', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: LanguageSelectionScreen())),
    );

    expect(find.text('Welcome to VYOM'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('हिंदी'), findsOneWidget);
  });
}
