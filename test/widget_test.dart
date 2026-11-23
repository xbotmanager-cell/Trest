import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hey_dane/app/app.dart';
import 'package:hey_dane/app/core/constants/app_identity.dart';

void main() {
  testWidgets('Splash screen renders HEY DANE branding and transitions',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: HeyDaneApp(initialLocation: '/splash'),
      ),
    );

    expect(find.text(AppIdentity.appName), findsOneWidget);
    expect(find.text(AppIdentity.tagline), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('Activate Voice'), findsOneWidget);
  });

  testWidgets('Main assistant screen navigates across shell tabs',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: HeyDaneApp(initialLocation: '/assistant'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppIdentity.appName), findsOneWidget);
    expect(find.text('Quick Actions'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('AI & System Settings'), findsOneWidget);
    expect(find.text('Default AI Provider'), findsOneWidget);
  });
}
