import 'package:flutter_test/flutter_test.dart';
import 'package:hey_dane/app/features/memory/services/memory_vault.dart';

class _InMemoryVault implements MemoryStore {
  List<MemoryRecord> _records = const [];

  @override
  Future<List<MemoryRecord>> loadPreferences() async => List.of(_records);

  @override
  Future<void> savePreferences(List<MemoryRecord> records) async {
    _records = List.of(records);
  }

  @override
  Future<void> clearAll() async {
    _records = const [];
  }
}

void main() {
  group('MemoryRecord & MemoryStore', () {
    test('serializes and deserializes MemoryRecord cleanly', () {
      final now = DateTime.utc(2026, 5, 1, 10, 30);
      final record = MemoryRecord(
        id: 'mem-1',
        label: 'Preferred Language',
        value: 'English & Swahili',
        savedAt: now,
      );

      final json = record.toJson();
      final restored = MemoryRecord.fromJson(json);

      expect(restored.id, 'mem-1');
      expect(restored.label, 'Preferred Language');
      expect(restored.value, 'English & Swahili');
      expect(restored.savedAt.toUtc(), now);
    });

    test('supports saving, updating, and wiping preferences in MemoryStore',
        () async {
      final store = _InMemoryVault();
      final r1 = MemoryRecord(
        id: '1',
        label: 'Briefing Time',
        value: '07:00',
        savedAt: DateTime.now(),
      );
      final r2 = MemoryRecord(
        id: '2',
        label: 'Voice Mode',
        value: 'Concise',
        savedAt: DateTime.now(),
      );

      await store.savePreferences([r1, r2]);
      expect((await store.loadPreferences()).length, 2);

      await store.savePreferences([r1]);
      final remaining = await store.loadPreferences();
      expect(remaining.length, 1);
      expect(remaining.single.id, '1');

      await store.clearAll();
      expect(await store.loadPreferences(), isEmpty);
    });
  });
}
