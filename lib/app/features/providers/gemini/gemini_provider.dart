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

class GeminiProvider implements AiProvider {
  GeminiProvider({
    http.Client? client,
    RetryPolicy? retryPolicy,
  })  : _client = client ?? http.Client(),
        _retryPolicy = retryPolicy ?? const RetryPolicy();

  final http.Client _client;
  final RetryPolicy _retryPolicy;

  static const String _googleApiBase =
      'https://generativelanguage.googleapis.com/v1beta';

  @override
  AiProviderKind get kind => AiProviderKind.gemini;

  @override
  List<String> get availableModels => const [
        'gemini-4-hydrogen',
        'gemini-4-neon',
        'gemini-3.1-flash-lite',
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
    final trimmedProxy = proxyBaseUrl?.trim();
    final trimmedKey = apiKey?.trim();

    if (trimmedProxy != null && trimmedProxy.isNotEmpty) {
      yield* _streamViaBackendProxy(
        request: request,
        proxyBaseUrl: trimmedProxy,
        cancellationToken: cancellationToken,
      );
      return;
    }

    if (trimmedKey == null || trimmedKey.isEmpty) {
      throw const AiException(
        kind: AiErrorKind.missingCredentials,
        providerId: 'gemini',
        message:
            'Configure either a Backend Proxy URL or a Gemini API key in API Manager.',
      );
    }

    yield* _streamDirect(
      request: request,
      apiKey: trimmedKey,
      cancellationToken: cancellationToken,
    );
  }

  Stream<AiStreamDelta> _streamViaBackendProxy({
    required AiRequest request,
    required String proxyBaseUrl,
    CancellationToken? cancellationToken,
  }) async* {
    final normalizedBase = proxyBaseUrl.replaceAll(RegExp(r'/+$'), '');
    final endpoint = Uri.parse('$normalizedBase/api/ai/chat');

    final streamedResponse = await _retryPolicy.execute<http.StreamedResponse>(
      () async {
        final req = http.Request('POST', endpoint)
          ..headers.addAll({
            'Content-Type': 'application/json',
            'Accept': 'text/event-stream',
          })
          ..body = jsonEncode({
            'prompt': request.prompt,
            'model': request.model,
            'history': [
              for (final msg in request.history)
                {'role': msg.role, 'text': msg.text},
            ],
            'attachments': [
              for (final att in request.attachments)
                {'mimeType': att.mimeType, 'base64Data': att.base64Data},
            ],
          });

        try {
          final res = await _client.send(req).timeout(request.timeout);
          if (res.statusCode >= 400) {
            final body = await res.stream.bytesToString();
            throw _mapHttpError(res.statusCode, body);
          }
          return res;
        } on TimeoutException {
          throw const AiException(
            kind: AiErrorKind.timeout,
            providerId: 'gemini',
            message: 'Backend proxy timed out.',
            retryable: true,
          );
        } on SocketException catch (e) {
          throw AiException(
            kind: AiErrorKind.network,
            providerId: 'gemini',
            message: 'Unable to reach backend proxy: ${e.message}',
            retryable: true,
          );
        } on http.ClientException catch (e) {
          throw AiException(
            kind: AiErrorKind.network,
            providerId: 'gemini',
            message: 'Unable to reach backend proxy: ${e.message}',
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
            providerId: 'gemini',
            message: 'Generation stopped.',
          );
        }
        for (final payload in decoder.addChunk(chunk)) {
          final delta = _parseProxyPayload(payload);
          if (delta != null) yield delta;
        }
      }
      for (final payload in decoder.flush()) {
        final delta = _parseProxyPayload(payload);
        if (delta != null) yield delta;
      }
    } on TimeoutException {
      throw const AiException(
        kind: AiErrorKind.timeout,
        providerId: 'gemini',
        message: 'Backend proxy stream timed out.',
        retryable: true,
      );
    } on SocketException catch (e) {
      throw AiException(
        kind: AiErrorKind.network,
        providerId: 'gemini',
        message: 'Backend proxy stream interrupted: ${e.message}',
        retryable: true,
      );
    } on http.ClientException catch (e) {
      throw AiException(
        kind: AiErrorKind.network,
        providerId: 'gemini',
        message: 'Backend proxy stream interrupted: ${e.message}',
        retryable: true,
      );
    } on FormatException catch (e) {
      throw AiException(
        kind: AiErrorKind.serverError,
        providerId: 'gemini',
        message: 'Invalid response from backend proxy: ${e.message}',
      );
    }
  }

  AiStreamDelta? _parseProxyPayload(String payload) {
    final parsed = jsonDecode(payload) as Map<String, dynamic>;
    if (parsed['error'] != null) {
      throw AiException(
        kind: AiErrorKind.serverError,
        providerId: 'gemini',
        message: parsed['error'].toString(),
      );
    }
    final text = (parsed['text'] as String?) ?? '';
    final rawUsage = parsed['usage'] as Map<String, dynamic>?;
    final usage = rawUsage != null
        ? TokenUsage(
            promptTokens: (rawUsage['promptTokens'] as num?)?.toInt() ?? 0,
            completionTokens:
                (rawUsage['completionTokens'] as num?)?.toInt() ?? 0,
            totalTokens: (rawUsage['totalTokens'] as num?)?.toInt() ?? 0,
          )
        : null;
    final done = parsed['done'] == true;
    if (text.isEmpty && usage == null && !done) return null;
    return AiStreamDelta(textDelta: text, usage: usage, isDone: done);
  }

  Stream<AiStreamDelta> _streamDirect({
    required AiRequest request,
    required String apiKey,
    CancellationToken? cancellationToken,
  }) async* {
    final contents = <Map<String, dynamic>>[
      for (final msg in request.history)
        {
          'role': msg.role == 'assistant' ? 'model' : 'user',
          'parts': [
            {'text': msg.text},
            for (final att in msg.attachments)
              {
                'inlineData': {
                  'mimeType': att.mimeType,
                  'data': att.base64Data,
                },
              },
          ],
        },
      {
        'role': 'user',
        'parts': [
          for (final att in request.attachments)
            {
              'inlineData': {
                'mimeType': att.mimeType,
                'data': att.base64Data,
              },
            },
          {'text': request.prompt},
        ],
      },
    ];

    final uri = Uri.parse(
      '$_googleApiBase/models/${request.model}:streamGenerateContent?alt=sse',
    );

    final streamedResponse = await _retryPolicy.execute<http.StreamedResponse>(
      () async {
        final httpReq = http.Request('POST', uri)
          ..headers.addAll({
            'x-goog-api-key': apiKey,
            'Content-Type': 'application/json',
            'Accept': 'text/event-stream',
          })
          ..body = jsonEncode({
            'contents': contents,
            if (request.systemInstruction != null &&
                request.systemInstruction!.trim().isNotEmpty)
              'systemInstruction': {
                'parts': [
                  {'text': request.systemInstruction},
                ],
              },
            if (request.maxTokens != null)
              'generationConfig': {
                'maxOutputTokens': request.maxTokens,
              },
          });

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
            providerId: 'gemini',
            message: 'Gemini request timed out.',
            retryable: true,
          );
        } on SocketException catch (e) {
          throw AiException(
            kind: AiErrorKind.network,
            providerId: 'gemini',
            message: 'Network error reaching Gemini: ${e.message}',
            retryable: true,
          );
        } on http.ClientException catch (e) {
          throw AiException(
            kind: AiErrorKind.network,
            providerId: 'gemini',
            message: 'Network error reaching Gemini: ${e.message}',
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
            providerId: 'gemini',
            message: 'Generation stopped.',
          );
        }

        for (final payload in decoder.addChunk(chunk)) {
          final delta = _parseGeminiChunk(payload);
          if (delta != null) {
            yield delta;
          }
        }
      }

      for (final payload in decoder.flush()) {
        final delta = _parseGeminiChunk(payload);
        if (delta != null) {
          yield delta;
        }
      }
    } on TimeoutException {
      throw const AiException(
        kind: AiErrorKind.timeout,
        providerId: 'gemini',
        message: 'Gemini stream timed out.',
        retryable: true,
      );
    } on SocketException catch (e) {
      throw AiException(
        kind: AiErrorKind.network,
        providerId: 'gemini',
        message: 'Gemini stream interrupted: ${e.message}',
        retryable: true,
      );
    } on http.ClientException catch (e) {
      throw AiException(
        kind: AiErrorKind.network,
        providerId: 'gemini',
        message: 'Gemini stream interrupted: ${e.message}',
        retryable: true,
      );
    } on FormatException catch (e) {
      throw AiException(
        kind: AiErrorKind.serverError,
        providerId: 'gemini',
        message: 'Invalid SSE response from Gemini: ${e.message}',
      );
    }
  }

  AiStreamDelta? _parseGeminiChunk(String payload) {
    final decoded = jsonDecode(payload) as Map<String, dynamic>;
    final streamError = decoded['error'];
    if (streamError != null) {
      final msg = streamError is Map<String, dynamic>
          ? (streamError['message']?.toString() ?? 'Gemini stream error.')
          : streamError.toString();
      throw AiException(
        kind: AiErrorKind.serverError,
        providerId: 'gemini',
        message: msg,
      );
    }

    final candidates = decoded['candidates'] as List<dynamic>? ?? const [];
    final buffer = StringBuffer();
    if (candidates.isNotEmpty) {
      final first = candidates.first as Map<String, dynamic>;
      final content = first['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List<dynamic>? ?? const [];
      for (final part in parts) {
        final text = (part as Map<String, dynamic>)['text'] as String?;
        if (text != null) {
          buffer.write(text);
        }
      }
    }

    TokenUsage? usage;
    final meta = decoded['usageMetadata'] as Map<String, dynamic>?;
    if (meta != null) {
      usage = TokenUsage(
        promptTokens: (meta['promptTokenCount'] as num?)?.toInt() ?? 0,
        completionTokens: (meta['candidatesTokenCount'] as num?)?.toInt() ?? 0,
        totalTokens: (meta['totalTokenCount'] as num?)?.toInt() ?? 0,
      );
    }

    final textOut = buffer.toString();
    if (textOut.isEmpty && usage == null) return null;
    return AiStreamDelta(textDelta: textOut, usage: usage);
  }

  @override
  Future<ProviderConnectionStatus> testConnection({
    required String model,
    required String? apiKey,
    String? proxyBaseUrl,
  }) async {
    final sw = Stopwatch()..start();
    final trimmedProxy = proxyBaseUrl?.trim();
    if (trimmedProxy != null && trimmedProxy.isNotEmpty) {
      try {
        final normalizedBase = trimmedProxy.replaceAll(RegExp(r'/+$'), '');
        final res = await _client
            .get(Uri.parse('$normalizedBase/api/health'))
            .timeout(const Duration(seconds: 10));
        sw.stop();
        if (res.statusCode == 200) {
          final json = jsonDecode(res.body) as Map<String, dynamic>;
          final configured = json['geminiConfigured'] == true;
          return ProviderConnectionStatus(
            provider: kind,
            reachable: configured,
            latencyMs: sw.elapsedMilliseconds,
            checkedAt: DateTime.now(),
            detail: configured
                ? 'Backend proxy connected (${sw.elapsedMilliseconds} ms).'
                : 'Proxy reachable, but GEMINI_API_KEY is not set on server.',
          );
        }
        return ProviderConnectionStatus(
          provider: kind,
          reachable: false,
          latencyMs: sw.elapsedMilliseconds,
          checkedAt: DateTime.now(),
          detail: 'Proxy returned HTTP ${res.statusCode}.',
        );
      } catch (e) {
        sw.stop();
        return ProviderConnectionStatus(
          provider: kind,
          reachable: false,
          latencyMs: sw.elapsedMilliseconds,
          checkedAt: DateTime.now(),
          detail: 'Proxy connection failed: $e',
        );
      }
    }

    final key = apiKey?.trim();
    if (key == null || key.isEmpty) {
      return ProviderConnectionStatus(
        provider: kind,
        reachable: false,
        latencyMs: 0,
        checkedAt: DateTime.now(),
        detail: 'Missing Gemini API key or proxy URL.',
      );
    }

    try {
      final response = await _client.get(
        Uri.parse('$_googleApiBase/models/$model'),
        headers: {'x-goog-api-key': key},
      ).timeout(const Duration(seconds: 12));
      sw.stop();
      if (response.statusCode == 200) {
        return ProviderConnectionStatus(
          provider: kind,
          reachable: true,
          latencyMs: sw.elapsedMilliseconds,
          checkedAt: DateTime.now(),
          detail: 'Connected (${sw.elapsedMilliseconds} ms) · $model ready.',
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
        detail: 'Gemini connection test timed out.',
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
        providerId: 'gemini',
        message: 'Gemini authentication failed: $safeDetail',
      );
    }
    if (statusCode == 429) {
      return AiException(
        kind: AiErrorKind.rateLimited,
        statusCode: statusCode,
        providerId: 'gemini',
        message: 'Gemini quota/rate limit reached: $safeDetail',
        retryable: true,
      );
    }
    if (statusCode >= 500) {
      return AiException(
        kind: AiErrorKind.serverError,
        statusCode: statusCode,
        providerId: 'gemini',
        message: 'Gemini server error: $safeDetail',
        retryable: true,
      );
    }
    return AiException(
      kind: AiErrorKind.badRequest,
      statusCode: statusCode,
      providerId: 'gemini',
      message: 'Gemini rejected request: $safeDetail',
    );
  }

  String? _extractSafeErrorMessage(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final err = json['error'];
      if (err is Map<String, dynamic>) {
        return err['message'] as String?;
      }
      if (err is String) return err;
      return null;
    } catch (_) {
      return null;
    }
  }
}
