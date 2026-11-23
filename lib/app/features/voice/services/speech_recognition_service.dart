import 'package:flutter/foundation.dart';
import 'package:hey_dane/app/features/voice/domain/voice_models.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

enum SpeechPermissionState {
  granted,
  denied,
  permanentlyDenied,
  unavailableOnHost,
}

abstract class SpeechRecognitionAdapter {
  Future<SpeechPermissionState> ensureMicrophonePermission();
  Future<bool> initialize({
    required void Function(String status) onStatus,
    required void Function(String message, bool permanent) onError,
  });
  Future<String?> resolveLocaleId(VoiceLocaleOption preferred);
  Future<void> startListening({
    required String? localeId,
    required void Function(String words, bool isFinal) onResult,
    required void Function(double normalizedLevel) onSoundLevel,
  });
  Future<void> stopListening();
  Future<void> cancelListening();
}

class DeviceSpeechRecognitionAdapter implements SpeechRecognitionAdapter {
  DeviceSpeechRecognitionAdapter({SpeechToText? stt})
      : _stt = stt ?? SpeechToText();

  final SpeechToText _stt;
  bool _initialized = false;

  @override
  Future<SpeechPermissionState> ensureMicrophonePermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return SpeechPermissionState.unavailableOnHost;
    }

    var status = await Permission.microphone.status;
    if (status.isGranted) return SpeechPermissionState.granted;

    status = await Permission.microphone.request();
    if (status.isGranted) return SpeechPermissionState.granted;
    if (status.isPermanentlyDenied) {
      return SpeechPermissionState.permanentlyDenied;
    }
    return SpeechPermissionState.denied;
  }

  @override
  Future<bool> initialize({
    required void Function(String status) onStatus,
    required void Function(String message, bool permanent) onError,
  }) async {
    if (_initialized && _stt.isAvailable) return true;

    _initialized = await _stt.initialize(
      onStatus: onStatus,
      onError: (SpeechRecognitionError err) {
        onError(err.errorMsg, err.permanent);
      },
    );
    return _initialized;
  }

  @override
  Future<String?> resolveLocaleId(VoiceLocaleOption preferred) async {
    if (!_initialized) return preferred.bcp47;
    final locales = await _stt.locales();
    if (locales.isEmpty) return preferred.bcp47;

    for (final tag in preferred.fallbackTags) {
      final normalizedTag = tag.replaceAll('-', '_').toLowerCase();
      for (final loc in locales) {
        if (loc.localeId.toLowerCase() == normalizedTag ||
            loc.localeId.toLowerCase().startsWith(normalizedTag)) {
          return loc.localeId;
        }
      }
    }
    return preferred.bcp47;
  }

  @override
  Future<void> startListening({
    required String? localeId,
    required void Function(String words, bool isFinal) onResult,
    required void Function(double normalizedLevel) onSoundLevel,
  }) async {
    await _stt.listen(
      listenOptions: SpeechListenOptions(
        localeId: localeId,
        listenMode: ListenMode.dictation,
        partialResults: true,
        cancelOnError: true,
      ),
      onResult: (SpeechRecognitionResult result) {
        onResult(result.recognizedWords, result.finalResult);
      },
      onSoundLevelChange: (double levelDb) {
        onSoundLevel(normalizeSoundLevelDb(levelDb));
      },
    );
  }

  /// Normalizes Android SpeechRecognizer sound level dB (typically -2..10 or -60..0)
  /// into a clean 0.0..1.0 intensity scalar without faking input.
  static double normalizeSoundLevelDb(double levelDb) {
    if (levelDb <= 0) {
      // Some OEMs emit negative dBFS (-60..0)
      return ((levelDb + 50.0) / 50.0).clamp(0.0, 1.0);
    }
    return (levelDb / 10.0).clamp(0.0, 1.0);
  }

  @override
  Future<void> stopListening() async {
    if (_stt.isListening) {
      await _stt.stop();
    }
  }

  @override
  Future<void> cancelListening() async {
    await _stt.cancel();
  }
}
