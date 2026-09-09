import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:honeychain/data/honeychain_store.dart';
import 'package:honeychain/screens/iot_simulator_screen.dart';
import 'package:honeychain/theme/app_theme.dart';

void main() {
  setUp(() {
    HoneyChainStore.testMode = true;
  });

  testWidgets('IoT simulator shows the not-configured hint without API_BASE_URL',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: IotSimulatorScreen()));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Compiled without API_BASE_URL'),
      findsOneWidget,
    );
    expect(find.textContaining('http://localhost:8000'), findsOneWidget);
  });

  testWidgets('simulator screen renders inside a themed scaffold', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.theme(),
        home: const IotSimulatorScreen(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(IotSimulatorScreen), findsOneWidget);
  });
}