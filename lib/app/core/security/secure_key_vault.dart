import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hey_dane/app/shared/providers/app_state_provider.dart';

abstract class KeyVaultStore {
  Future<String?> readKey(AiProviderKind provider);
  Future<void> writeKey(AiProviderKind provider, String apiKey);
  Future<void> deleteKey(AiProviderKind provider);
  Future<String?> readProxyBaseUrl();
  Future<void> writeProxyBaseUrl(String url);
}

class SecureKeyVault implements KeyVaultStore {
  SecureKeyVault({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
              ),
            );

  final FlutterSecureStorage _storage;

  static String _providerKeyName(AiProviderKind provider) =>
      'hey_dane_api_key_${provider.name}';

  static const String _proxyUrlKey = 'hey_dane_proxy_base_url';

  @override
  Future<String?> readKey(AiProviderKind provider) async {
    final value = await _storage.read(key: _providerKeyName(provider));
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  @override
  Future<void> writeKey(AiProviderKind provider, String apiKey) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      await deleteKey(provider);
      return;
    }
    await _storage.write(key: _providerKeyName(provider), value: trimmed);
  }

  @override
  Future<void> deleteKey(AiProviderKind provider) async {
    await _storage.delete(key: _providerKeyName(provider));
  }

  @override
  Future<String?> readProxyBaseUrl() async {
    final value = await _storage.read(key: _proxyUrlKey);
    if (value == null || value.trim().isEmpty) return null;
    return value.trim();
  }

  @override
  Future<void> writeProxyBaseUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      await _storage.delete(key: _proxyUrlKey);
      return;
    }
    await _storage.write(key: _proxyUrlKey, value: trimmed);
  }

  static String maskApiKey(String? rawKey) {
    final trimmed = rawKey?.trim() ?? '';
    if (trimmed.isEmpty) return 'Not configured';
    if (trimmed.length <= 8) return '••••••••';
    final prefix = trimmed.substring(0, 4);
    final suffix = trimmed.substring(trimmed.length - 4);
    return '$prefix••••••••$suffix';
  }
}
