import 'package:hey_dane/app/features/providers/domain/ai_models.dart';
import 'package:hey_dane/app/shared/providers/app_state_provider.dart';

abstract class AiProvider {
  AiProviderKind get kind;

  List<String> get availableModels;

  bool get supportsVision;

  Stream<AiStreamDelta> streamCompletion({
    required AiRequest request,
    required String? apiKey,
    String? proxyBaseUrl,
    CancellationToken? cancellationToken,
  });

  Future<ProviderConnectionStatus> testConnection({
    required String model,
    required String? apiKey,
    String? proxyBaseUrl,
  });
}
