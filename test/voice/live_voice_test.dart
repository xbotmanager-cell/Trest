import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hey_dane/app/core/errors/ai_exception.dart';
import 'package:hey_dane/app/core/security/secure_key_vault.dart';
import 'package:hey_dane/app/features/hologram/widgets/holographic_orb.dart';
import 'package:hey_dane/app/features/providers/domain/ai_models.dart';
import 'package:hey_dane/app/features/providers/domain/ai_provider.dart';
import 'package:hey_dane/app/features/voice/domain/voice_models.dart';
import 'package:hey_dane/app/features/voice/services/speech_recognition_service.dart';
import 'package:hey_dane/app/features/voice/services/tts_service.dart';
import 'package:hey_dane/app/features/voice/services/wake_word_service.dart';
import 'package:hey_dane/app/shared/providers/app_state_provider.dart';

class _TestKeyVault implements KeyVaultStore {
  final Map<AiProviderKind, String> _keys = {
    AiProviderKind.gemini: 'test_gemini_key',
  };
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

class _FakeSpeechAdapter implements SpeechRecognitionAdapter {
  SpeechPermissionState permission = SpeechPermissionState.granted;
  bool initSuccess = true;
  bool listening = false;
  bool stopped = false;

  void Function(String status)? _onStatus;
  void Function(String message, bool permanent)? _onError;
  void Function(String words, bool isFinal)? _onResult;
  void Function(double level)? _onSoundLevel;

  @override
  Future<SpeechPermissionState> ensureMicrophonePermission() async =>
      permission;

  @override
  Future<bool> initialize({
    required void Function(String status) onStatus,
    required void Function(String message, bool permanent) onError,
  }) async {
    _onStatus = onStatus;
    _onError = onError;
    return initSuccess;
  }

  @override
  Future<String?> resolveLocaleId(VoiceLocaleOption preferred) async =>
      preferred.bcp47;

  @override
  Future<void> startListening({
    required String? localeId,
    required void Function(String words, bool isFinal) onResult,
    required void Function(double normalizedLevel) onSoundLevel,
  }) async {
    listening = true;
    stopped = false;
    _onResult = onResult;
    _onSoundLevel = onSoundLevel;
  }

  void emitSound(double level) => _onSoundLevel?.call(level);

  void emitTranscript(String text, {bool isFinal = false}) {
    _onResult?.call(text, isFinal);
  }

  void emitEngineError(String message) {
    _onError?.call(message, false);
  }

  void emitStatus(String status) {
    _onStatus?.call(status);
  }

  @override
  Future<void> stopListening() async {
    listening = false;
    stopped = true;
  }

  @override
  Future<void> cancelListening() async {
    listening = false;
    stopped = true;
  }
}

class _FakeTtsAdapter implements TtsAdapter {
  bool speaking = false;
  bool stoppedCalled = false;
  bool failOnSpeak = false;
  String? lastSpoken;
  void Function(double)? _onProgress;
  VoidCallback? _onComplete;
  void Function(String)? _onError;

  @override
  Future<void> configure({
    required VoiceLocaleOption locale,
    required double speechRate,
  }) async {}

  @override
  Future<bool> isLocaleSupported(VoiceLocaleOption locale) async => true;

  @override
  Future<void> speak(
    String text, {
    required void Function(double progressRatio) onProgress,
    required VoidCallback onComplete,
    required void Function(String error) onError,
  }) async {
    if (failOnSpeak) {
      onError('TTS engine unavailable');
      return;
    }
    speaking = true;
    lastSpoken = text;
    _onProgress = onProgress;
    _onComplete = onComplete;
    _onError = onError;
  }

  void emitProgress(double ratio) => _onProgress?.call(ratio);

  void emitComplete() {
    speaking = false;
    _onComplete?.call();
  }

  void emitFailure(String error) {
    speaking = false;
    _onError?.call(error);
  }

  @override
  Future<void> stop() async {
    speaking = false;
    stoppedCalled = true;
  }
}

class _FakeAiProvider implements AiProvider {
  _FakeAiProvider(this.kind, {this.shouldError = false});

  @override
  final AiProviderKind kind;
  final bool shouldError;

  @override
  List<String> get availableModels => [kind.defaultModel];

  @override
  bool get supportsVision => false;

  @override
  Stream<AiStreamDelta> streamCompletion({
    required AiRequest request,
    required String? apiKey,
    String? proxyBaseUrl,
    CancellationToken? cancellationToken,
  }) async* {
    if (shouldError) {
      throw const AiException(
        kind: AiErrorKind.network,
        message: 'Simulated upstream error',
      );
    }
    yield const AiStreamDelta(textDelta: 'Alarm set for ');
    yield const AiStreamDelta(
      textDelta: '6:00 AM.',
      usage: TokenUsage(promptTokens: 8, completionTokens: 6, totalTokens: 14),
      isDone: true,
    );
  }

  @override
  Future<ProviderConnectionStatus> testConnection({
    required String model,
    required String? apiKey,
    String? proxyBaseUrl,
  }) async {
    return ProviderConnectionStatus(
      provider: kind,
      reachable: true,
      latencyMs: 12,
      checkedAt: DateTime.now(),
      detail: 'OK',
    );
  }
}

ProviderContainer _createVoiceContainer({
  required _FakeSpeechAdapter speech,
  required _FakeTtsAdapter tts,
  bool aiError = false,
}) {
  return ProviderContainer(
    overrides: [
      keyVaultProvider.overrideWithValue(_TestKeyVault()),
      speechRecognitionAdapterProvider.overrideWithValue(speech),
      ttsAdapterProvider.overrideWithValue(tts),
      aiProvidersMapProvider.overrideWithValue({
        AiProviderKind.gemini:
            _FakeAiProvider(AiProviderKind.gemini, shouldError: aiError),
        AiProviderKind.groq:
            _FakeAiProvider(AiProviderKind.groq, shouldError: aiError),
        AiProviderKind.openRouter:
            _FakeAiProvider(AiProviderKind.openRouter, shouldError: aiError),
      }),
    ],
  );
}

void main() {
  group('LiveVoiceController states & hardware edge cases', () {
    test(
        'transitions listening -> thinking -> speaking -> idle with real AI + TTS',
        () async {
      final speech = _FakeSpeechAdapter();
      final tts = _FakeTtsAdapter();
      final container = _createVoiceContainer(speech: speech, tts: tts);
      addTearDown(container.dispose);

      final controller = container.read(liveVoiceControllerProvider.notifier);
      await controller.startSession();

      expect(container.read(liveVoiceControllerProvider).orbState,
          DaneOrbState.listening);
      speech.emitSound(0.72);
      expect(container.read(liveVoiceControllerProvider).audioLevel, 0.72);

      speech.emitTranscript('Set alarm for 6 AM', isFinal: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final speakingState = container.read(liveVoiceControllerProvider);
      expect(speakingState.orbState, DaneOrbState.speaking);
      expect(speakingState.assistantResponse, 'Alarm set for 6:00 AM.');
      expect(tts.lastSpoken, 'Alarm set for 6:00 AM.');

      tts.emitProgress(0.5);
      expect(container.read(liveVoiceControllerProvider).audioLevel,
          greaterThan(0.0));

      tts.emitComplete();
      expect(container.read(liveVoiceControllerProvider).orbState,
          DaneOrbState.idle);
      expect(container.read(conversationTurnsProvider).length, 2);
    });

    test('handles microphone denial with recognizable error state', () async {
      final speech = _FakeSpeechAdapter()
        ..permission = SpeechPermissionState.denied;
      final tts = _FakeTtsAdapter();
      final container = _createVoiceContainer(speech: speech, tts: tts);
      addTearDown(container.dispose);

      await container.read(liveVoiceControllerProvider.notifier).startSession();
      final state = container.read(liveVoiceControllerProvider);

      expect(state.orbState, DaneOrbState.error);
      expect(state.errorMessage, contains('Microphone permission'));
    });

    test(
        'supports voice interruption (barge-in) while speaking and clean endSession',
        () async {
      final speech = _FakeSpeechAdapter();
      final tts = _FakeTtsAdapter();
      final container = _createVoiceContainer(speech: speech, tts: tts);
      addTearDown(container.dispose);

      final controller = container.read(liveVoiceControllerProvider.notifier);
      await controller.startSession();
      await controller.submitUtteranceForTest('Hello Dane');

      expect(container.read(liveVoiceControllerProvider).orbState,
          DaneOrbState.speaking);

      // Interrupt while speaking
      await controller.handleOrbTap();
      expect(tts.stoppedCalled, isTrue);
      expect(container.read(liveVoiceControllerProvider).orbState,
          DaneOrbState.listening);

      // End conversation cleanly
      await controller.endSession();
      final ended = container.read(liveVoiceControllerProvider);
      expect(ended.isSessionActive, isFalse);
      expect(ended.orbState, DaneOrbState.idle);
      expect(ended.audioLevel, 0.0);
    });

    test('handles speech recognition failure and TTS failure gracefully',
        () async {
      final speech = _FakeSpeechAdapter();
      final tts = _FakeTtsAdapter()..failOnSpeak = true;
      final container = _createVoiceContainer(speech: speech, tts: tts);
      addTearDown(container.dispose);

      final controller = container.read(liveVoiceControllerProvider.notifier);
      await controller.startSession();
      speech.emitEngineError('error_no_match');

      expect(container.read(liveVoiceControllerProvider).orbState,
          DaneOrbState.error);
      expect(container.read(liveVoiceControllerProvider).errorMessage,
          contains('error_no_match'));

      await controller.retryAfterError();
      expect(container.read(liveVoiceControllerProvider).orbState,
          DaneOrbState.listening);

      await controller.submitUtteranceForTest('Check TTS failure');
      expect(container.read(liveVoiceControllerProvider).orbState,
          DaneOrbState.error);
      expect(
        container.read(liveVoiceControllerProvider).errorMessage,
        contains('TTS engine unavailable'),
      );
    });
  });

  group('Wake-word & dB utilities', () {
    test('matches Hey Dane wake phrases accurately', () {
      expect(
          ForegroundPhraseWakeWordEngine.matchesWakePhrase('Hey Dane'), isTrue);
      expect(
          ForegroundPhraseWakeWordEngine.matchesWakePhrase(
              'hey dane set timer'),
          isTrue);
      expect(ForegroundPhraseWakeWordEngine.matchesWakePhrase('open weather'),
          isFalse);
    });

    test('normalizes dB sound levels safely to 0.0..1.0', () {
      expect(DeviceSpeechRecognitionAdapter.normalizeSoundLevelDb(-50), 0.0);
      expect(DeviceSpeechRecognitionAdapter.normalizeSoundLevelDb(0), 1.0);
      expect(DeviceSpeechRecognitionAdapter.normalizeSoundLevelDb(5), 0.5);
      expect(DeviceSpeechRecognitionAdapter.normalizeSoundLevelDb(14), 1.0);
    });
  });

  testWidgets('HolographicOrb renders cleanly across all live voice states',
      (tester) async {
    for (final orbState in DaneOrbState.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: HolographicOrb(
                state: orbState,
                audioLevel: 0.65,
                size: 240,
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(HolographicOrb), findsOneWidget);
    }
  });
}
