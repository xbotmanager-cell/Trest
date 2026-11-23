import 'package:hey_dane/app/core/errors/ai_exception.dart';
import 'package:hey_dane/app/core/security/secure_key_vault.dart';
import 'package:hey_dane/app/features/providers/domain/ai_models.dart';
import 'package:hey_dane/app/features/providers/domain/ai_provider.dart';
import 'package:hey_dane/app/shared/providers/app_state_provider.dart';

class RoutedStreamEvent {
  const RoutedStreamEvent({
    required this.providerUsed,
    required this.modelUsed,
    required this.delta,
    this.usedFallback = false,
  });

  final AiProviderKind providerUsed;
  final String modelUsed;
  final AiStreamDelta delta;
  final bool usedFallback;
}

class AiRouterService {
  AiRouterService({
    required Map<AiProviderKind, AiProvider> providers,
    required KeyVaultStore keyVault,
  })  : _providers = providers,
        _keyVault = keyVault;

  final Map<AiProviderKind, AiProvider> _providers;
  final KeyVaultStore _keyVault;

  AiProvider providerFor(AiProviderKind kind) {
    final provider = _providers[kind];
    if (provider == null) {
      throw AiException(
        kind: AiErrorKind.unknown,
        message: 'Provider ${kind.label} is not registered.',
      );
    }
    return provider;
  }

  Stream<RoutedStreamEvent> streamWithFallback({
    required AiProviderKind primaryKind,
    required String primaryModel,
    required AiRequest request,
    bool allowOpenRouterFallback = true,
    String? openRouterFallbackModel,
    List<AiProviderKind>? fallbackOrder,
    Map<AiProviderKind, String>? selectedModels,
    CancellationToken? cancellationToken,
  }) async* {
    final primaryProvider = providerFor(primaryKind);
    final primaryKey = await _keyVault.readKey(primaryKind);
    final proxyUrl = await _keyVault.readProxyBaseUrl();

    final errors = <String>[];
    var emittedAnyText = false;

    try {
      await for (final delta in primaryProvider.streamCompletion(
        request: AiRequest(
          prompt: request.prompt,
          model: primaryModel,
          history: request.history,
          attachments: request.attachments,
          systemInstruction: request.systemInstruction,
          maxTokens: request.maxTokens,
          timeout: request.timeout,
        ),
        apiKey: primaryKey,
        proxyBaseUrl: proxyUrl,
        cancellationToken: cancellationToken,
      )) {
        if (delta.textDelta.isNotEmpty) {
          emittedAnyText = true;
        }
        yield RoutedStreamEvent(
          providerUsed: primaryKind,
          modelUsed: primaryModel,
          delta: delta,
        );
      }
      return;
    } on AiException catch (primaryError) {
      if (primaryError.kind == AiErrorKind.cancelled || emittedAnyText) {
        rethrow;
      }
      errors.add('${primaryKind.label}: ${primaryError.message}');

      if (!allowOpenRouterFallback) {
        rethrow;
      }

      final candidates = (fallbackOrder ?? const [AiProviderKind.openRouter])
          .where((k) => k != primaryKind)
          .toList();

      if (candidates.isEmpty) {
        rethrow;
      }

      for (final candidateKind in candidates) {
        final candidateKey = await _keyVault.readKey(candidateKind);
        final hasProxyForGemini = candidateKind == AiProviderKind.gemini &&
            proxyUrl != null &&
            proxyUrl.trim().isNotEmpty;
        if ((candidateKey == null || candidateKey.trim().isEmpty) &&
            !hasProxyForGemini) {
          continue;
        }

        final fallbackProvider = providerFor(candidateKind);
        final fallbackModel = candidateKind == AiProviderKind.openRouter &&
                openRouterFallbackModel != null
            ? openRouterFallbackModel
            : (selectedModels?[candidateKind] ??
                fallbackProvider.availableModels.first);

        try {
          await for (final delta in fallbackProvider.streamCompletion(
            request: AiRequest(
              prompt: request.prompt,
              model: fallbackModel,
              history: request.history,
              attachments: request.attachments,
              systemInstruction: request.systemInstruction,
              maxTokens: request.maxTokens,
              timeout: request.timeout,
            ),
            apiKey: candidateKey,
            proxyBaseUrl: proxyUrl,
            cancellationToken: cancellationToken,
          )) {
            yield RoutedStreamEvent(
              providerUsed: candidateKind,
              modelUsed: fallbackModel,
              delta: delta,
              usedFallback: true,
            );
          }
          return;
        } on AiException catch (fallbackError) {
          if (fallbackError.kind == AiErrorKind.cancelled) {
            rethrow;
          }
          errors.add('${candidateKind.label}: ${fallbackError.message}');
        }
      }

      if (errors.length == 1) {
        rethrow;
      }

      throw AiException(
        kind: primaryError.kind,
        statusCode: primaryError.statusCode,
        providerId: primaryError.providerId,
        message: 'All configured AI providers failed (${errors.join(' | ')}).',
      );
    }
  }

  Future<AiCompletionResult> generateComplete({
    required AiProviderKind primaryKind,
    required String primaryModel,
    required AiRequest request,
    bool allowFallback = true,
    List<AiProviderKind>? fallbackOrder,
    Map<AiProviderKind, String>? selectedModels,
    CancellationToken? cancellationToken,
  }) async {
    final buffer = StringBuffer();
    AiProviderKind usedProvider = primaryKind;
    String usedModel = primaryModel;
    var usedFallback = false;
    TokenUsage? usage;

    await for (final event in streamWithFallback(
      primaryKind: primaryKind,
      primaryModel: primaryModel,
      request: request,
      allowOpenRouterFallback: allowFallback,
      fallbackOrder: fallbackOrder,
      selectedModels: selectedModels,
      cancellationToken: cancellationToken,
    )) {
      usedProvider = event.providerUsed;
      usedModel = event.modelUsed;
      usedFallback = event.usedFallback;
      if (event.delta.textDelta.isNotEmpty) {
        buffer.write(event.delta.textDelta);
      }
      if (event.delta.usage != null) {
        usage = event.delta.usage;
      }
    }

    return AiCompletionResult(
      text: buffer.toString(),
      providerUsed: usedProvider,
      modelUsed: usedModel,
      usedFallback: usedFallback,
      usage: usage,
    );
  }

  Future<ProviderConnectionStatus> testProvider({
    required AiProviderKind kind,
    required String model,
  }) async {
    final provider = providerFor(kind);
    final apiKey = await _keyVault.readKey(kind);
    final proxyUrl = await _keyVault.readProxyBaseUrl();
    return provider.testConnection(
      model: model,
      apiKey: apiKey,
      proxyBaseUrl: proxyUrl,
    );
  }
}
