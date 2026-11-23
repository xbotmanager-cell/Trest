import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:hey_dane/app/core/errors/ai_exception.dart';
import 'package:hey_dane/app/core/networking/retry_policy.dart';
import 'package:hey_dane/app/core/networking/sse_parser.dart';
import 'package:hey_dane/app/features/providers/domain/ai_models.dart';
import 'package:hey_dane/app/features/providers/domain/ai_provider.dart';
import 'package:hey_dane/app/shared/providers/app_state_provider.dart';

class OpenRouterProvider implements AiProvider {
  OpenRouterProvider({
    http.Client? client,
    RetryPolicy? retryPolicy,
  })  : _client = client ?? http.Client(),
        _retryPolicy = retryPolicy ?? const RetryPolicy();

  final http.Client _client;
  final RetryPolicy _retryPolicy;

  static const String _baseUrl = 'https://openrouter.ai/api/v1';

  @override
  AiProviderKind get kind => AiProviderKind.openRouter;

  @override
  List<String> get availableModels => const [
        'anthropic/claude-sonnet-4',
        'anthropic/claude-3.5-sonnet',
        'openai/gpt-4o-mini',
        'google/gemini-2.5-flash',
        'meta-llama/llama-3.3-70b-instruct',
      ];

  @override
  bool get supportsVision => true;

  @override
  Stream<AiStreamDelta> streamCompletion({
    required AiRequest request,
    required String? apiKey,
    String? proxyBaseUrl,
    CancellationToken? cancellationToken,
  }) async* {
    final key = apiKey?.trim();
    if (key == null || key.isEmpty) {
      throw const AiException(
        kind: AiErrorKind.missingCredentials,
        providerId: 'openrouter',
        message: 'OpenRouter API key is not configured. Add a key in API Manager.',
      );
    }

    final messages = <Map<String, dynamic>>[
      if (request.systemInstruction != null &&
          request.systemInstruction!.trim().isNotEmpty)
        {'role': 'system', 'content': request.systemInstruction},
      for (final msg in request.history)
        {'role': msg.role, 'content': msg.text},
      if (request.attachments.isEmpty)
        {'role': 'user', 'content': request.prompt}
      else
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': request.prompt},
            for (final att in request.attachments)
              {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:${att.mimeType};base64,${att.base64Data}',
                },
              },
          ],
        },
    ];

    final payloadMap = <String, dynamic>{
      'model': request.model,
      'messages': messages,
      'stream': true,
      'stream_options': {'include_usage': true},
      if (request.maxTokens != null) 'max_tokens': request.maxTokens,
    };

    final streamedResponse = await _retryPolicy.execute<http.StreamedResponse>(
      () async {
        final httpReq = http.Request(
          'POST',
          Uri.parse('$_baseUrl/chat/completions'),
        )
          ..headers.addAll({
            'Authorization': 'Bearer $key',
            'Content-Type': 'application/json',
            'Accept': 'text/event-stream',
            'HTTP-Referer': 'https://heydane.app',
            'X-Title': 'HEY DANE',
          })
          ..body = jsonEncode(payloadMap);

        try {
          final response = await _client.send(httpReq).timeout(request.timeout);
          if (response.statusCode >= 400) {
            final body = await response.stream.bytesToString();
            throw _mapHttpError(response.statusCode, body);
          }
          return response;
        } on TimeoutException {
          throw const AiException(
            kind: AiErrorKind.timeout,
            providerId: 'openrouter',
            message: 'OpenRouter request timed out.',
            retryable: true,
          );
        } on SocketException catch (e) {
          throw AiException(
            kind: AiErrorKind.network,
            providerId: 'openrouter',
            message: 'Network error reaching OpenRouter: ${e.message}',
            retryable: true,
          );
        } on http.ClientException catch (e) {
          throw AiException(
            kind: AiErrorKind.network,
            providerId: 'openrouter',
            message: 'Network error reaching OpenRouter: ${e.message}',
            retryable: true,
          );
        }
      },
      isCancelled: () => cancellationToken?.isCancelled ?? false,
    );

    final decoder = SseEventDecoder();
    try {
      await for (final chunk
          in streamedResponse.stream.timeout(request.timeout)) {
        if (cancellationToken?.isCancelled == true) {
          throw const AiException(
            kind: AiErrorKind.cancelled,
            providerId: 'openrouter',
            message: 'Generation stopped.',
          );
        }
        for (final payload in decoder.addChunk(chunk)) {
          final delta = _parseSsePayload(payload);
          if (delta != null) yield delta;
        }
      }

      for (final payload in decoder.flush()) {
        final delta = _parseSsePayload(payload);
        if (delta != null) yield delta;
      }
    } on TimeoutException {
      throw const AiException(
        kind: AiErrorKind.timeout,
        providerId: 'openrouter',
        message: 'OpenRouter stream timed out.',
        retryable: true,
      );
    } on SocketException catch (e) {
      throw AiException(
        kind: AiErrorKind.network,
        providerId: 'openrouter',
        message: 'OpenRouter stream interrupted: ${e.message}',
        retryable: true,
      );
    } on http.ClientException catch (e) {
      throw AiException(
        kind: AiErrorKind.network,
        providerId: 'openrouter',
        message: 'OpenRouter stream interrupted: ${e.message}',
        retryable: true,
      );
    } on FormatException catch (e) {
      throw AiException(
        kind: AiErrorKind.serverError,
        providerId: 'openrouter',
        message: 'Invalid SSE response from OpenRouter: ${e.message}',
      );
    }
  }

  AiStreamDelta? _parseSsePayload(String payload) {
    if (payload == '[DONE]') {
      return const AiStreamDelta(textDelta: '', isDone: true);
    }

    final decoded = jsonDecode(payload) as Map<String, dynamic>;
    final streamError = decoded['error'];
    if (streamError != null) {
      final msg = streamError is Map<String, dynamic>
          ? (streamError['message']?.toString() ?? 'OpenRouter stream error.')
          : streamError.toString();
      throw AiException(
        kind: AiErrorKind.serverError,
        providerId: 'openrouter',
        message: msg,
      );
    }

    final choices = decoded['choices'] as List<dynamic>? ?? const [];
    var text = '';
    if (choices.isNotEmpty) {
      final first = choices.first as Map<String, dynamic>;
      final delta = first['delta'] as Map<String, dynamic>?;
      text = (delta?['content'] as String?) ?? '';
    }

    TokenUsage? usage;
    final rawUsage = decoded['usage'] as Map<String, dynamic>?;
    if (rawUsage != null) {
      usage = TokenUsage(
        promptTokens: (rawUsage['prompt_tokens'] as num?)?.toInt() ?? 0,
        completionTokens: (rawUsage['completion_tokens'] as num?)?.toInt() ?? 0,
        totalTokens: (rawUsage['total_tokens'] as num?)?.toInt() ?? 0,
      );
    }

    if (text.isEmpty && usage == null) return null;
    return AiStreamDelta(textDelta: text, usage: usage);
  }

  @override
  Future<ProviderConnectionStatus> testConnection({
    required String model,
    required String? apiKey,
    String? proxyBaseUrl,
  }) async {
    final key = apiKey?.trim();
    if (key == null || key.isEmpty) {
      return ProviderConnectionStatus(
        provider: kind,
        reachable: false,
        latencyMs: 0,
        checkedAt: DateTime.now(),
        detail: 'Missing OpenRouter API key.',
      );
    }

    final sw = Stopwatch()..start();
    try {
      final response = await _client
          .get(
            Uri.parse('$_baseUrl/auth/key'),
            headers: {'Authorization': 'Bearer $key'},
          )
          .timeout(const Duration(seconds: 12));
      sw.stop();

      if (response.statusCode == 200) {
        var labelSuffix = '';
        try {
          final parsed = jsonDecode(response.body) as Map<String, dynamic>;
          final data = parsed['data'] as Map<String, dynamic>?;
          final label = data?['label']?.toString().trim();
          if (label != null && label.isNotEmpty) {
            labelSuffix = ' · key "$label"';
          }
        } catch (_) {}
        return ProviderConnectionStatus(
          provider: kind,
          reachable: true,
          latencyMs: sw.elapsedMilliseconds,
          checkedAt: DateTime.now(),
          detail:
              'Connected (${sw.elapsedMilliseconds} ms)$labelSuffix · $model ready.',
        );
      }

      final mapped = _mapHttpError(response.statusCode, response.body);
      return ProviderConnectionStatus(
        provider: kind,
        reachable: false,
        latencyMs: sw.elapsedMilliseconds,
        checkedAt: DateTime.now(),
        detail: mapped.message,
      );
    } on TimeoutException {
      sw.stop();
      return ProviderConnectionStatus(
        provider: kind,
        reachable: false,
        latencyMs: sw.elapsedMilliseconds,
        checkedAt: DateTime.now(),
        detail: 'OpenRouter connection test timed out.',
      );
    } catch (e) {
      sw.stop();
      return ProviderConnectionStatus(
        provider: kind,
        reachable: false,
        latencyMs: sw.elapsedMilliseconds,
        checkedAt: DateTime.now(),
        detail: 'Connection test failed: $e',
      );
    }
  }

  AiException _mapHttpError(int statusCode, String body) {
    final safeDetail = _extractSafeErrorMessage(body) ?? 'HTTP $statusCode';
    if (statusCode == 401 || statusCode == 403) {
      return AiException(
        kind: AiErrorKind.unauthorized,
        statusCode: statusCode,
        providerId: 'openrouter',
        message: 'OpenRouter authentication failed: $safeDetail',
      );
    }
    if (statusCode == 429) {
      return AiException(
        kind: AiErrorKind.rateLimited,
        statusCode: statusCode,
        providerId: 'openrouter',
        message: 'OpenRouter rate limit exceeded: $safeDetail',
        retryable: true,
      );
    }
    if (statusCode >= 500) {
      return AiException(
        kind: AiErrorKind.serverError,
        statusCode: statusCode,
        providerId: 'openrouter',
        message: 'OpenRouter server error: $safeDetail',
        retryable: true,
      );
    }
    return AiException(
      kind: AiErrorKind.badRequest,
      statusCode: statusCode,
      providerId: 'openrouter',
      message: 'OpenRouter rejected request: $safeDetail',
    );
  }

  String? _extractSafeErrorMessage(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final err = json['error'] as Map<String, dynamic>?;
      return err?['message'] as String?;
    } catch (_) {
      return null;
    }
  }
}
