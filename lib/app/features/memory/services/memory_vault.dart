import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class MemoryRecord {
  const MemoryRecord({
    required this.id,
    required this.label,
    required this.value,
    required this.savedAt,
  });

  final String id;
  final String label;
  final String value;
  final DateTime savedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'value': value,
        'savedAt': savedAt.toIso8601String(),
      };

  factory MemoryRecord.fromJson(Map<String, dynamic> json) {
    return MemoryRecord(
      id: (json['id'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      value: (json['value'] ?? '').toString(),
      savedAt: DateTime.tryParse((json['savedAt'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}

abstract class MemoryStore {
  Future<List<MemoryRecord>> loadPreferences();
  Future<void> savePreferences(List<MemoryRecord> records);
  Future<void> clearAll();
}

class EncryptedMemoryVault implements MemoryStore {
  EncryptedMemoryVault({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;
  static const String _prefsKey = 'hey_dane_encrypted_memory_prefs';

  @override
  Future<List<MemoryRecord>> loadPreferences() async {
    final raw = await _storage.read(key: _prefsKey);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(MemoryRecord.fromJson)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> savePreferences(List<MemoryRecord> records) async {
    final encoded = jsonEncode(records.map((r) => r.toJson()).toList());
    await _storage.write(key: _prefsKey, value: encoded);
  }

  @override
  Future<void> clearAll() async {
    await _storage.delete(key: _prefsKey);
  }
}
