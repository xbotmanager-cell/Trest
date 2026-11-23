import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hey_dane/app/core/errors/ai_exception.dart';
import 'package:hey_dane/app/features/providers/domain/ai_models.dart';
import 'package:hey_dane/app/features/voice/domain/voice_models.dart';
import 'package:hey_dane/app/features/voice/services/speech_recognition_service.dart';
import 'package:hey_dane/app/features/voice/services/tts_service.dart';
import 'package:hey_dane/app/features/voice/services/wake_word_service.dart';
import 'package:hey_dane/app/shared/providers/app_state_provider.dart';
import 'package:uuid/uuid.dart';

class LiveVoiceController extends StateNotifier<VoiceSessionState> {
  LiveVoiceController({
    required Ref ref,
    required SpeechRecognitionAdapter speechAdapter,
    required TtsAdapter ttsAdapter,
    required WakeWordEngine wakeWordEngine,
  })  : _ref = ref,
        _speech = speechAdapter,
        _tts = ttsAdapter,
        _wakeWord = wakeWordEngine,
        super(const VoiceSessionState());

  final Ref _ref;
  final SpeechRecognitionAdapter _speech;
  final TtsAdapter _tts;
  final WakeWordEngine _wakeWord;
  final Uuid _uuid = const Uuid();

  CancellationToken? _activeCancellation;
  bool _disposed = false;
  int _speakPulseStep = 0;

  void _syncOrbState(DaneOrbState next) {
    if (_disposed) return;
    _ref.read(orbStateProvider.notifier).state = next;
  }

  Future<void> startSession() async {
    if (state.isSessionActive && state.orbState == DaneOrbState.listening) return;

    await _wakeWord.disarm();
    state = state.copyWith(
      isSessionActive: true,
      clearError: true,
      liveTranscript: '',
      assistantResponse: '',
      audioLevel: 0.0,
    );
    await _beginListeningTurn();
  }

  Future<void> _beginListeningTurn() async {
    if (!state.isSessionActive || state.isMicMuted) {
      state = state.copyWith(orbState: DaneOrbState.idle, audioLevel: 0.0);
      _syncOrbState(DaneOrbState.idle);
      return;
    }

    await _tts.stop();

    final permission = await _speech.ensureMicrophonePermission();
    if (permission != SpeechPermissionState.granted) {
      final msg = switch (permission) {
        SpeechPermissionState.permanentlyDenied =>
          'Microphone permission is permanently denied. Enable RECORD_AUDIO in Android App Settings.',
        SpeechPermissionState.denied =>
          'Microphone permission is required for live voice conversation.',
        SpeechPermissionState.unavailableOnHost =>
          'Live speech capture requires an Android microphone device.',
        SpeechPermissionState.granted => '',
      };
      state = state.copyWith(
        orbState: DaneOrbState.error,
        errorMessage: msg,
        audioLevel: 0.0,
      );
      _syncOrbState(DaneOrbState.error);
      return;
    }

    final available = await _speech.initialize(
      onStatus: (status) {
        if (!state.isSessionActive) return;
        if (status == 'done' &&
            state.orbState == DaneOrbState.listening &&
            state.liveTranscript.trim().isEmpty) {
          // User stayed silent; return cleanly to idle ready state.
          state = state.copyWith(orbState: DaneOrbState.idle, audioLevel: 0.0);
          _syncOrbState(DaneOrbState.idle);
        }
      },
      onError: (msg, permanent) {
        if (!state.isSessionActive) return;
        if (state.orbState == DaneOrbState.listening) {
          state = state.copyWith(
            orbState: DaneOrbState.error,
            errorMessage: 'Speech recognition error: $msg',
            audioLevel: 0.0,
          );
          _syncOrbState(DaneOrbState.error);
        }
      },
    );

    if (!available) {
      state = state.copyWith(
        orbState: DaneOrbState.error,
        errorMessage:
            'Speech recognition engine is unavailable on this device.',
        audioLevel: 0.0,
      );
      _syncOrbState(DaneOrbState.error);
      return;
    }

    final localeId = await _speech.resolveLocaleId(state.locale);

    state = state.copyWith(
      orbState: DaneOrbState.listening,
      clearError: true,
      liveTranscript: '',
      audioLevel: 0.05,
    );
    _syncOrbState(DaneOrbState.listening);

    await _speech.startListening(
      localeId: localeId,
      onSoundLevel: (normalized) {
        if (!state.isSessionActive || state.orbState != DaneOrbState.listening) {
          return;
        }
        state = state.copyWith(audioLevel: normalized);
      },
      onResult: (words, isFinal) {
        if (!state.isSessionActive) return;
        state = state.copyWith(liveTranscript: words);
        if (isFinal && words.trim().isNotEmpty) {
          unawaited(_processSpokenTurn(words.trim()));
        }
      },
    );
  }

  /// Processes a finalized user utterance through the existing AI router
  /// and speaks the response via TTS.
  Future<void> submitUtteranceForTest(String transcript) async {
    state = state.copyWith(
      isSessionActive: true,
      liveTranscript: transcript,
      clearError: true,
    );
    await _processSpokenTurn(transcript);
  }

  Future<void> _processSpokenTurn(String transcript) async {
    await _speech.stopListening();
    if (!state.isSessionActive) return;

    final providerKind = _ref.read(activeProviderKindProvider);
    final models = _ref.read(selectedModelsProvider);
    final model = models[providerKind] ?? providerKind.defaultModel;
    final allowFallback = _ref.read(openRouterFallbackProvider);
    final fallbackOrder = _ref.read(fallbackOrderProvider);
    final fallbackModel = models[AiProviderKind.openRouter];

    final existingTurns = _ref.read(conversationTurnsProvider);
    final history = existingTurns
        .where((t) => !t.isError && t.text.trim().isNotEmpty)
        .map((t) => AiMessageInput(role: t.isUser ? 'user' : 'assistant', text: t.text))
        .toList();

    final userTurn = ChatTurn(
      id: _uuid.v4(),
      isUser: true,
      text: transcript,
      timestamp: DateTime.now(),
    );
    final assistantId = _uuid.v4();
    final assistantTurn = ChatTurn(
      id: assistantId,
      isUser: false,
      text: '',
      timestamp: DateTime.now(),
      providerLabel: providerKind.label,
      modelLabel: model,
      isStreaming: true,
      sourcePrompt: transcript,
    );

    _ref.read(conversationTurnsProvider.notifier).state = [
      ...existingTurns,
      userTurn,
      assistantTurn,
    ];

    state = state.copyWith(
      orbState: DaneOrbState.thinking,
      assistantResponse: '',
      audioLevel: 0.25,
    );
    _syncOrbState(DaneOrbState.thinking);

    final cancellation = CancellationToken();
    _activeCancellation = cancellation;
    final router = _ref.read(aiRouterServiceProvider);
    final buffer = StringBuffer();
    TokenUsage? latestUsage;

    try {
      final languageHint = state.locale == VoiceLocaleOption.swahili
          ? 'Reply concisely in natural Swahili unless the user explicitly switches to English.'
          : 'Reply concisely in natural spoken English.';

      await for (final event in router.streamWithFallback(
        primaryKind: providerKind,
        primaryModel: model,
        allowOpenRouterFallback: allowFallback,
        fallbackOrder: fallbackOrder,
        selectedModels: models,
        openRouterFallbackModel: fallbackModel,
        cancellationToken: cancellation,
        request: AiRequest(
          prompt: transcript,
          model: model,
          history: history,
          systemInstruction:
              'You are Dane, the personal AI assistant in HEY DANE. '
              '$languageHint Keep answers clear and conversational for voice playback.',
        ),
      )) {
        if (cancellation.isCancelled || !state.isSessionActive) return;

        if (event.delta.textDelta.isNotEmpty) {
          buffer.write(event.delta.textDelta);
          state = state.copyWith(assistantResponse: buffer.toString());
        }
        if (event.delta.usage != null) {
          latestUsage = event.delta.usage;
        }
      }

      final finalReply = buffer.toString().trim();
      if (latestUsage != null) {
        final total = _ref.read(sessionTokenUsageProvider);
        _ref.read(sessionTokenUsageProvider.notifier).state = total + latestUsage;
      }

      _updateChatTurn(
        assistantId,
        (t) => t.copyWith(
          text: finalReply.isEmpty ? 'No response received.' : finalReply,
          isError: finalReply.isEmpty,
          isStreaming: false,
          usage: latestUsage,
        ),
      );

      if (finalReply.isEmpty) {
        state = state.copyWith(
          orbState: DaneOrbState.error,
          errorMessage: 'Provider returned an empty response.',
          audioLevel: 0.0,
        );
        _syncOrbState(DaneOrbState.error);
        return;
      }

      await _speakResponse(finalReply);
    } on AiException catch (err) {
      if (err.kind == AiErrorKind.cancelled) return;
      _updateChatTurn(
        assistantId,
        (t) => t.copyWith(text: err.message, isError: true, isStreaming: false),
      );
      state = state.copyWith(
        orbState: DaneOrbState.error,
        errorMessage: err.message,
        audioLevel: 0.0,
      );
      _syncOrbState(DaneOrbState.error);
    } catch (err) {
      final msg = 'Voice request failed: $err';
      _updateChatTurn(
        assistantId,
        (t) => t.copyWith(text: msg, isError: true, isStreaming: false),
      );
      state = state.copyWith(
        orbState: DaneOrbState.error,
        errorMessage: msg,
        audioLevel: 0.0,
      );
      _syncOrbState(DaneOrbState.error);
    } finally {
      _activeCancellation = null;
    }
  }

  Future<void> _speakResponse(String reply) async {
    if (!state.isSessionActive) return;

    if (state.isSpeakerMuted) {
      state = state.copyWith(
        orbState: DaneOrbState.idle,
        audioLevel: 0.0,
      );
      _syncOrbState(DaneOrbState.idle);
      return;
    }

    await _tts.configure(locale: state.locale, speechRate: state.speechRate);

    state = state.copyWith(
      orbState: DaneOrbState.speaking,
      audioLevel: 0.45,
      clearError: true,
    );
    _syncOrbState(DaneOrbState.speaking);

    await _tts.speak(
      reply,
      onProgress: (progressRatio) {
        if (!state.isSessionActive || state.orbState != DaneOrbState.speaking) {
          return;
        }
        _speakPulseStep += 1;
        // Modulate orb amplitude cleanly from genuine TTS word progress callbacks.
        final cadence = 0.42 + 0.45 * ((math.sin(_speakPulseStep * 1.15) + 1) / 2);
        state = state.copyWith(audioLevel: cadence.clamp(0.25, 0.95));
      },
      onComplete: () {
        if (!state.isSessionActive) return;
        state = state.copyWith(
          orbState: DaneOrbState.idle,
          audioLevel: 0.0,
        );
        _syncOrbState(DaneOrbState.idle);
      },
      onError: (errMsg) {
        if (!state.isSessionActive) return;
        state = state.copyWith(
          orbState: DaneOrbState.error,
          errorMessage: errMsg,
          audioLevel: 0.0,
        );
        _syncOrbState(DaneOrbState.error);
      },
    );
  }

  Future<void> handleOrbTap() async {
    switch (state.orbState) {
      case DaneOrbState.idle:
        await _beginListeningTurn();
      case DaneOrbState.listening:
        await _speech.stopListening();
        if (state.liveTranscript.trim().isNotEmpty) {
          await _processSpokenTurn(state.liveTranscript.trim());
        } else {
          state = state.copyWith(orbState: DaneOrbState.idle, audioLevel: 0.0);
          _syncOrbState(DaneOrbState.idle);
        }
      case DaneOrbState.thinking:
        _activeCancellation?.cancel();
        state = state.copyWith(orbState: DaneOrbState.idle, audioLevel: 0.0);
        _syncOrbState(DaneOrbState.idle);
      case DaneOrbState.speaking:
        // Voice interruption (barge-in): immediately stop TTS and listen to user.
        await _tts.stop();
        await _beginListeningTurn();
      case DaneOrbState.error:
        await retryAfterError();
    }
  }

  Future<void> retryAfterError() async {
    state = state.copyWith(clearError: true, audioLevel: 0.0);
    await _beginListeningTurn();
  }

  void returnToIdle() {
    state = state.copyWith(
      orbState: DaneOrbState.idle,
      clearError: true,
      audioLevel: 0.0,
    );
    _syncOrbState(DaneOrbState.idle);
  }

  Future<void> toggleMicMute() async {
    final nextMuted = !state.isMicMuted;
    state = state.copyWith(isMicMuted: nextMuted);
    if (nextMuted && state.orbState == DaneOrbState.listening) {
      await _speech.cancelListening();
      state = state.copyWith(orbState: DaneOrbState.idle, audioLevel: 0.0);
      _syncOrbState(DaneOrbState.idle);
    }
  }

  Future<void> toggleSpeakerMute() async {
    final nextMuted = !state.isSpeakerMuted;
    state = state.copyWith(isSpeakerMuted: nextMuted);
    if (nextMuted && state.orbState == DaneOrbState.speaking) {
      await _tts.stop();
      state = state.copyWith(orbState: DaneOrbState.idle, audioLevel: 0.0);
      _syncOrbState(DaneOrbState.idle);
    }
  }

  Future<void> setLocale(VoiceLocaleOption locale) async {
    state = state.copyWith(locale: locale);
    await _tts.configure(locale: locale, speechRate: state.speechRate);
  }

  Future<void> setSpeechRate(double rate) async {
    final clamped = rate.clamp(0.25, 0.85);
    state = state.copyWith(speechRate: clamped);
    await _tts.configure(locale: state.locale, speechRate: clamped);
  }

  Future<void> toggleWakeWord(bool enable, {void Function()? onTriggered}) async {
    if (!enable) {
      await _wakeWord.disarm();
      _ref.read(wakeWordEnabledProvider.notifier).state = false;
      state = state.copyWith(
        wakeWordArmed: false,
        wakeWordStatusNote: 'Manual voice activation active',
      );
      return;
    }

    final ok = await _wakeWord.arm(
      locale: state.locale,
      onWakeDetected: () {
        _ref.read(wakeWordEnabledProvider.notifier).state = false;
        state = state.copyWith(
          wakeWordArmed: false,
          wakeWordStatusNote: ForegroundPhraseWakeWordEngine.confirmationGreeting,
        );
        onTriggered?.call();
      },
      onUnavailable: (reason) {
        _ref.read(wakeWordEnabledProvider.notifier).state = false;
        state = state.copyWith(
          wakeWordArmed: false,
          wakeWordStatusNote: reason,
        );
      },
    );

    _ref.read(wakeWordEnabledProvider.notifier).state = ok;
    state = state.copyWith(
      wakeWordArmed: ok,
      wakeWordStatusNote: ok
          ? 'Foreground wake-phrase listening armed ("Hey Dane")'
          : state.wakeWordStatusNote,
    );
  }

  Future<void> endSession() async {
    _activeCancellation?.cancel();
    _activeCancellation = null;
    await _speech.cancelListening();
    await _tts.stop();
    state = state.copyWith(
      isSessionActive: false,
      orbState: DaneOrbState.idle,
      audioLevel: 0.0,
      clearError: true,
    );
    _syncOrbState(DaneOrbState.idle);
  }

  void _updateChatTurn(String id, ChatTurn Function(ChatTurn) transform) {
    final current = _ref.read(conversationTurnsProvider);
    _ref.read(conversationTurnsProvider.notifier).state = [
      for (final t in current)
        if (t.id == id) transform(t) else t,
    ];
  }

  @override
  void dispose() {
    _disposed = true;
    _activeCancellation?.cancel();
    unawaited(_speech.cancelListening());
    unawaited(_tts.stop());
    unawaited(_wakeWord.disarm());
    super.dispose();
  }
}
