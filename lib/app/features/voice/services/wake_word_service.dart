import 'package:hey_dane/app/core/constants/app_identity.dart';
import 'package:hey_dane/app/features/voice/domain/voice_models.dart';
import 'package:hey_dane/app/features/voice/services/speech_recognition_service.dart';

enum WakeWordAvailability {
  foregroundActiveOnly(
    'Foreground Wake-Phrase Ready',
    'Android restricts system-level always-on hotword DSP (CAPTURE_AUDIO_HOTWORD) to preinstalled system apps. '
        'HEY DANE supports foreground wake-phrase monitoring when armed with microphone permission, plus manual tap activation anytime.',
  ),
  microphoneDenied(
    'Microphone Permission Required',
    'Grant RECORD_AUDIO to enable wake-phrase monitoring. Manual text & settings remain available.',
  ),
  unsupportedHost(
    'Android Hardware Required',
    'Wake-phrase monitoring requires an Android device microphone and speech recognition engine.',
  );

  const WakeWordAvailability(this.title, this.explanation);
  final String title;
  final String explanation;
}

abstract class WakeWordEngine {
  bool get isArmed;
  Future<WakeWordAvailability> checkAvailability();
  Future<bool> arm({
    required VoiceLocaleOption locale,
    required void Function() onWakeDetected,
    required void Function(String reason) onUnavailable,
  });
  Future<void> disarm();
}

/// Modular local wake-phrase detector using on-device speech transcripts
/// without continuously streaming raw microphone audio to cloud LLMs.
class ForegroundPhraseWakeWordEngine implements WakeWordEngine {
  ForegroundPhraseWakeWordEngine({
    required SpeechRecognitionAdapter speechAdapter,
  }) : _speech = speechAdapter;

  final SpeechRecognitionAdapter _speech;
  bool _armed = false;

  static final RegExp _wakePattern = RegExp(
    r'\b(hey\s+dane|hey\s+dean|hey\s+dayne|dane)\b',
    caseSensitive: false,
  );

  @override
  bool get isArmed => _armed;

  @override
  Future<WakeWordAvailability> checkAvailability() async {
    final perm = await _speech.ensureMicrophonePermission();
    return switch (perm) {
      SpeechPermissionState.granted =>
        WakeWordAvailability.foregroundActiveOnly,
      SpeechPermissionState.denied ||
      SpeechPermissionState.permanentlyDenied =>
        WakeWordAvailability.microphoneDenied,
      SpeechPermissionState.unavailableOnHost =>
        WakeWordAvailability.unsupportedHost,
    };
  }

  static bool matchesWakePhrase(String transcript) {
    return _wakePattern.hasMatch(transcript.trim());
  }

  @override
  Future<bool> arm({
    required VoiceLocaleOption locale,
    required void Function() onWakeDetected,
    required void Function(String reason) onUnavailable,
  }) async {
    final perm = await _speech.ensureMicrophonePermission();
    if (perm != SpeechPermissionState.granted) {
      onUnavailable(WakeWordAvailability.microphoneDenied.explanation);
      return false;
    }

    final initialized = await _speech.initialize(
      onStatus: (_) {},
      onError: (msg, _) {
        if (_armed) {
          _armed = false;
          onUnavailable('Speech engine stopped wake listening: $msg');
        }
      },
    );

    if (!initialized) {
      onUnavailable('Device speech recognition service is unavailable.');
      return false;
    }

    _armed = true;
    final localeId = await _speech.resolveLocaleId(locale);
    await _speech.startListening(
      localeId: localeId,
      onSoundLevel: (_) {},
      onResult: (words, isFinal) async {
        if (!_armed) return;
        if (matchesWakePhrase(words)) {
          _armed = false;
          await _speech.stopListening();
          onWakeDetected();
        } else if (isFinal && _armed) {
          // Restart short foreground wake window cleanly without sending audio to cloud AI.
          await _speech.stopListening();
        }
      },
    );
    return true;
  }

  @override
  Future<void> disarm() async {
    _armed = false;
    await _speech.stopListening();
  }

  static String get confirmationGreeting =>
      'Yes, I\'m listening. (${AppIdentity.wakePhrase})';
}
