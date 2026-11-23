import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hey_dane/app/features/about/about_screen.dart';
import 'package:hey_dane/app/features/automation/automation_screen.dart';
import 'package:hey_dane/app/features/memory/memory_screen.dart';
import 'package:hey_dane/app/features/memory/services/memory_vault.dart';
import 'package:hey_dane/app/features/permissions/permissions_screen.dart';
import 'package:hey_dane/app/features/permissions/services/permission_center_service.dart';
import 'package:hey_dane/app/shared/providers/app_state_provider.dart';

class _TestMemoryStore implements MemoryStore {
  List<MemoryRecord> items = [
    MemoryRecord(
      id: 'p1',
      label: 'Wake Mode',
      value: 'Foreground Only',
      savedAt: DateTime(2026, 5, 1),
    ),
  ];

  @override
  Future<void> clearAll() async => items = const [];

  @override
  Future<List<MemoryRecord>> loadPreferences() async => items;

  @override
  Future<void> savePreferences(List<MemoryRecord> records) async {
    items = List.of(records);
  }
}

void main() {
  test('SpecialAccessSnapshot counts enabled Android special privileges', () {
    const empty = SpecialAccessSnapshot();
    expect(empty.enabledSpecialCount, 0);

    const partial = SpecialAccessSnapshot(
      accessibilityEnabled: true,
      notificationAccessEnabled: true,
      exactAlarmEnabled: true,
    );
    expect(partial.enabledSpecialCount, 3);
  });

  testWidgets('PermissionsScreen renders setup progress and toggles',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: PermissionsScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Permission Center'), findsOneWidget);
    expect(find.text('Setup Progress'), findsOneWidget);
    expect(find.text('Runtime Permissions'), findsOneWidget);
  });

  testWidgets('AutomationScreen, MemoryScreen, and AboutScreen render cleanly',
      (tester) async {
    final fakeMemory = _TestMemoryStore();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          memoryVaultProvider.overrideWithValue(fakeMemory),
        ],
        child: const MaterialApp(home: AutomationScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Device Automation'), findsOneWidget);
    expect(find.text('Structured Action Pipeline'), findsOneWidget);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          memoryVaultProvider.overrideWithValue(fakeMemory),
        ],
        child: const MaterialApp(home: MemoryScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Encrypted Memory Vault'), findsOneWidget);
    expect(find.text('Wake Mode'), findsOneWidget);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          memoryVaultProvider.overrideWithValue(fakeMemory),
        ],
        child: const MaterialApp(home: AboutScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('About & Privacy'), findsOneWidget);
  });
}
