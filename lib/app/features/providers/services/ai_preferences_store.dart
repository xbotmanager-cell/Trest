import 'package:hey_dane/app/shared/providers/app_state_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AiRoutingPreferences {
  const AiRoutingPreferences({
    this.defaultProvider = AiProviderKind.gemini,
    this.selectedModels = const {},
    this.fallbackEnabled = true,
    this.fallbackOrder = const [
      AiProviderKind.openRouter,
      AiProviderKind.groq,
      AiProviderKind.gemini,
    ],
  });

  final AiProviderKind defaultProvider;
  final Map<AiProviderKind, String> selectedModels;
  final bool fallbackEnabled;
  final List<AiProviderKind> fallbackOrder;
}

/// Persists non-secret AI routing preferences (never API keys).
abstract class AiPreferencesStore {
  Future<AiRoutingPreferences> load();
  Future<void> saveDefaultProvider(AiProviderKind kind);
  Future<void> saveSelectedModels(Map<AiProviderKind, String> models);
  Future<void> saveFallbackEnabled(bool enabled);
  Future<void> saveFallbackOrder(List<AiProviderKind> order);
}

class SharedPrefsAiPreferencesStore implements AiPreferencesStore {
  static const String _defaultProviderKey = 'hey_dane_default_provider';
  static const String _fallbackEnabledKey = 'hey_dane_fallback_enabled';
  static const String _fallbackOrderKey = 'hey_dane_fallback_order';
  static String _modelKey(AiProviderKind kind) =>
      'hey_dane_selected_model_${kind.name}';

  static AiProviderKind? _parseKind(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final k in AiProviderKind.values) {
      if (k.name == raw) return k;
    }
    return null;
  }

  @override
  Future<AiRoutingPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    final defaultKind =
        _parseKind(prefs.getString(_defaultProviderKey)) ??
            AiProviderKind.gemini;
    final fallbackEnabled = prefs.getBool(_fallbackEnabledKey) ?? true;

    final rawOrder = prefs.getStringList(_fallbackOrderKey);
    final parsedOrder = <AiProviderKind>[];
    if (rawOrder != null) {
      for (final name in rawOrder) {
        final k = _parseKind(name);
        if (k != null && !parsedOrder.contains(k)) {
          parsedOrder.add(k);
        }
      }
    }
    for (final k in const [
      AiProviderKind.openRouter,
      AiProviderKind.groq,
      AiProviderKind.gemini,
    ]) {
      if (!parsedOrder.contains(k)) {
        parsedOrder.add(k);
      }
    }

    final models = <AiProviderKind, String>{};
    for (final k in AiProviderKind.values) {
      final savedModel = prefs.getString(_modelKey(k));
      if (savedModel != null && savedModel.trim().isNotEmpty) {
        models[k] = savedModel.trim();
      }
    }

    return AiRoutingPreferences(
      defaultProvider: defaultKind,
      selectedModels: models,
      fallbackEnabled: fallbackEnabled,
      fallbackOrder: parsedOrder,
    );
  }

  @override
  Future<void> saveDefaultProvider(AiProviderKind kind) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultProviderKey, kind.name);
  }

  @override
  Future<void> saveSelectedModels(Map<AiProviderKind, String> models) async {
    final prefs = await SharedPreferences.getInstance();
    for (final entry in models.entries) {
      await prefs.setString(_modelKey(entry.key), entry.value);
    }
  }

  @override
  Future<void> saveFallbackEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_fallbackEnabledKey, enabled);
  }

  @override
  Future<void> saveFallbackOrder(List<AiProviderKind> order) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _fallbackOrderKey,
      order.map((k) => k.name).toList(),
    );
  }
}
