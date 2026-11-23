import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hey_dane/app/core/errors/ai_exception.dart';
import 'package:hey_dane/app/core/networking/retry_policy.dart';
import 'package:hey_dane/app/core/security/secure_key_vault.dart';
import 'package:hey_dane/app/features/providers/domain/ai_models.dart';
import 'package:hey_dane/app/features/providers/gemini/gemini_provider.dart';
import 'package:hey_dane/app/features/providers/groq/groq_provider.dart';
import 'package:hey_dane/app/features/providers/openrouter/openrouter_provider.dart';
import 'package:hey_dane/app/features/providers/services/ai_router_service.dart';
import 'package:hey_dane/app/shared/providers/app_state_provider.dart';

class _MemoryKeyVault implements KeyVaultStore {
  final Map<AiProviderKind, String> _keys = {};
  String? _proxyUrl;

  @override
  Future<void> deleteKey(AiProviderKind provider) async =>
      _keys.remove(provider);

  @override
  Future<String?> readKey(AiProviderKind provider) async => _keys[provider];

  @override
  Future<String?> readProxyBaseUrl() async => _proxyUrl;

  @override
  Future<void> writeKey(AiProviderKind provider, String apiKey) async {
    _keys[provider] = apiKey;
  }

  @override
  Future<void> writeProxyBaseUrl(String url) async {
    _proxyUrl = url;
  }
}

void main() {
  group('GroqProvider', () {
    test('parses SSE chunks and token usage from Groq stream', () async {
      final client = MockClient.streaming((request, bodyStream) async {
        expect(request.headers['Authorization'], 'Bearer gsk_test');
        final sse = [
          'data: {"choices":[{"delta":{"content":"Hello "}}]}\n\n',
          'data: {"choices":[{"delta":{"content":"Dane"}}],"x_groq":{"usage":{"prompt_tokens":10,"completion_tokens":4,"total_tokens":14}}}\n\n',
          'data: [DONE]\n\n',
        ].join();
        return http.StreamedResponse(
          Stream.value(utf8.encode(sse)),
          200,
          headers: {'content-type': 'text/event-stream'},
        );
      });

      final provider = GroqProvider(
        client: client,
        retryPolicy: const RetryPolicy(
          maxAttempts: 2,
          initialDelay: Duration(milliseconds: 1),
        ),
      );

      final deltas = await provider
          .streamCompletion(
            request: const AiRequest(
              prompt: 'Hi',
              model: 'llama-3.3-70b-versatile',
            ),
            apiKey: 'gsk_test',
          )
          .toList();

      expect(deltas.map((d) => d.textDelta).join(), 'Hello Dane');
      final usageDelta = deltas.firstWhere((d) => d.usage != null);
      expect(usageDelta.usage!.totalTokens, 14);
    });

    test('retries transient 503 error and succeeds on second attempt',
        () async {
      var calls = 0;
      final client = MockClient.streaming((request, bodyStream) async {
        calls++;
        if (calls == 1) {
          return http.StreamedResponse(
            Stream.value(utf8.encode('{"error":{"message":"Busy"}}')),
            503,
          );
        }
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(
                'data: {"choices":[{"delta":{"content":"Recovered"}}]}\n\n'),
          ),
          200,
        );
      });

      final provider = GroqProvider(
        client: client,
        retryPolicy: const RetryPolicy(
          maxAttempts: 2,
          initialDelay: Duration(milliseconds: 1),
        ),
      );

      final deltas = await provider
          .streamCompletion(
            request: const AiRequest(
              prompt: 'Hi',
              model: 'llama-3.3-70b-versatile',
            ),
            apiKey: 'gsk_test',
          )
          .toList();

      expect(calls, 2);
      expect(deltas.map((d) => d.textDelta).join(), 'Recovered');
    });
  });

  group('GeminiProvider', () {
    test('sends multimodal inlineData and parses usageMetadata', () async {
      final client = MockClient.streaming((request, bodyStream) async {
        final rawBody = await bodyStream.bytesToString();
        final decoded = jsonDecode(rawBody) as Map<String, dynamic>;
        final contents = decoded['contents'] as List<dynamic>;
        final parts =
            (contents.last as Map<String, dynamic>)['parts'] as List<dynamic>;
        expect(parts.length, 2);
        expect(parts.first['inlineData']['mimeType'], 'image/png');

        const sse =
            'data: {"candidates":[{"content":{"parts":[{"text":"Image analyzed."}]}}],"usageMetadata":{"promptTokenCount":25,"candidatesTokenCount":5,"totalTokenCount":30}}\n\n';
        return http.StreamedResponse(
          Stream.value(utf8.encode(sse)),
          200,
        );
      });

      final provider = GeminiProvider(client: client);
      final deltas = await provider
          .streamCompletion(
            request: const AiRequest(
              prompt: 'Describe',
              model: 'gemini-4-hydrogen',
              attachments: [
                AiAttachment(mimeType: 'image/png', base64Data: 'AAAA'),
              ],
            ),
            apiKey: 'gem_test',
          )
          .toList();

      expect(deltas.single.textDelta, 'Image analyzed.');
      expect(deltas.single.usage?.totalTokens, 30);
    });

    test('fails explicitly when neither key nor proxy URL is set', () async {
      final provider = GeminiProvider(
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      expect(
        () => provider
            .streamCompletion(
              request: const AiRequest(
                prompt: 'Hi',
                model: 'gemini-4-hydrogen',
              ),
              apiKey: null,
            )
            .toList(),
        throwsA(
          isA<AiException>().having(
            (e) => e.kind,
            'kind',
            AiErrorKind.missingCredentials,
          ),
        ),
      );
    });
  });

  group('AiRouterService fallback', () {
    test('falls back to OpenRouter when primary provider fails with 401',
        () async {
      final vault = _MemoryKeyVault();
      await vault.writeKey(AiProviderKind.groq, 'bad_key');
      await vault.writeKey(AiProviderKind.openRouter, 'or_valid_key');

      final groqClient = MockClient.streaming((req, _) async {
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"error":{"message":"Invalid key"}}')),
          401,
        );
      });

      final openRouterClient = MockClient.streaming((req, _) async {
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(
              'data: {"choices":[{"delta":{"content":"Fallback ok"}}]}\n\n',
            ),
          ),
          200,
        );
      });

      final router = AiRouterService(
        providers: {
          AiProviderKind.groq: GroqProvider(
            client: groqClient,
            retryPolicy: const RetryPolicy(maxAttempts: 1),
          ),
          AiProviderKind.gemini: GeminiProvider(),
          AiProviderKind.openRouter:
              OpenRouterProvider(client: openRouterClient),
        },
        keyVault: vault,
      );

      final events = await router
          .streamWithFallback(
            primaryKind: AiProviderKind.groq,
            primaryModel: 'llama-3.3-70b-versatile',
            request: const AiRequest(
              prompt: 'Hello',
              model: 'llama-3.3-70b-versatile',
            ),
          )
          .toList();

      expect(events.single.usedFallback, isTrue);
      expect(events.single.providerUsed, AiProviderKind.openRouter);
      expect(events.single.delta.textDelta, 'Fallback ok');
    });
  });
}
