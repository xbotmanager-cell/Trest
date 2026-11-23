import 'package:hey_dane/app/shared/providers/app_state_provider.dart';

class TokenUsage {
  const TokenUsage({
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.totalTokens = 0,
  });

  final int promptTokens;
  final int completionTokens;
  final int totalTokens;

  TokenUsage operator +(TokenUsage other) {
    return TokenUsage(
      promptTokens: promptTokens + other.promptTokens,
      completionTokens: completionTokens + other.completionTokens,
      totalTokens: totalTokens + other.totalTokens,
    );
  }
}

class AiAttachment {
  const AiAttachment({
    required this.mimeType,
    required this.base64Data,
  });

  final String mimeType;
  final String base64Data;
}

class AiMessageInput {
  const AiMessageInput({
    required this.role,
    required this.text,
    this.attachments = const [],
  });

  final String role; // 'user' | 'assistant' | 'system'
  final String text;
  final List<AiAttachment> attachments;
}

class AiRequest {
  const AiRequest({
    required this.prompt,
    required this.model,
    this.history = const [],
    this.attachments = const [],
    this.systemInstruction,
    this.maxTokens,
    this.timeout = const Duration(seconds: 35),
  });

  final String prompt;
  final String model;
  final List<AiMessageInput> history;
  final List<AiAttachment> attachments;
  final String? systemInstruction;
  final int? maxTokens;
  final Duration timeout;
}

class AiStreamDelta {
  const AiStreamDelta({
    required this.textDelta,
    this.usage,
    this.isDone = false,
  });

  final String textDelta;
  final TokenUsage? usage;
  final bool isDone;
}

class AiCompletionResult {
  const AiCompletionResult({
    required this.text,
    required this.providerUsed,
    required this.modelUsed,
    this.usedFallback = false,
    this.usage,
  });

  final String text;
  final AiProviderKind providerUsed;
  final String modelUsed;
  final bool usedFallback;
  final TokenUsage? usage;
}

class ProviderConnectionStatus {
  const ProviderConnectionStatus({
    required this.provider,
    required this.reachable,
    required this.latencyMs,
    required this.checkedAt,
    required this.detail,
  });

  final AiProviderKind provider;
  final bool reachable;
  final int latencyMs;
  final DateTime checkedAt;
  final String detail;
}

class ProviderConfiguration {
  const ProviderConfiguration({
    required this.provider,
    required this.model,
    required this.hasApiKey,
    this.proxyBaseUrl,
    this.enableFallback = true,
  });

  final AiProviderKind provider;
  final String model;
  final bool hasApiKey;
  final String? proxyBaseUrl;
  final bool enableFallback;

  bool get canUseProxy =>
      proxyBaseUrl != null && proxyBaseUrl!.trim().isNotEmpty;
}

class CancellationToken {
  bool _cancelled = false;
  final List<void Function()> _listeners = [];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in List<void Function()>.from(_listeners)) {
      listener();
    }
    _listeners.clear();
  }

  void addListener(void Function() listener) {
    if (_cancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }
}
