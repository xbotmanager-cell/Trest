import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:hey_dane/app/features/voice/domain/voice_models.dart';

abstract class TtsAdapter {
  Future<bool> isLocaleSupported(VoiceLocaleOption locale);
  Future<void> configure({
    required VoiceLocaleOption locale,
    required double speechRate,
  });
  Future<void> speak(
    String text, {
    required void Function(double progressRatio) onProgress,
    required VoidCallback onComplete,
    required void Function(String error) onError,
  });
  Future<void> stop();
}

class DeviceTtsAdapter implements TtsAdapter {
  DeviceTtsAdapter({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  bool _handlersBound = false;

  void Function(double progressRatio)? _onProgress;
  VoidCallback? _onComplete;
  void Function(String error)? _onError;

  void _ensureHandlers() {
    if (_handlersBound) return;
    _handlersBound = true;

    _tts.setProgressHandler((String text, int start, int end, String word) {
      if (text.isEmpty) return;
      final ratio = (end / text.length).clamp(0.0, 1.0);
      _onProgress?.call(ratio);
    });

    _tts.setCompletionHandler(() {
      _onComplete?.call();
    });

    _tts.setCancelHandler(() {
      _onComplete?.call();
    });

    _tts.setErrorHandler((dynamic msg) {
      _onError?.call(msg?.toString() ?? 'Text-to-speech playback error.');
    });
  }

  @override
  Future<bool> isLocaleSupported(VoiceLocaleOption locale) async {
    for (final tag in locale.fallbackTags) {
      try {
        final available = await _tts.isLanguageAvailable(tag);
        if (available == true || available == 1) return true;
      } catch (_) {}
    }
    return false;
  }

  @override
  Future<void> configure({
    required VoiceLocaleOption locale,
    required double speechRate,
  }) async {
    _ensureHandlers();
    await _tts.awaitSpeakCompletion(false);
    await _tts.setSpeechRate(speechRate.clamp(0.25, 0.85));
    await _tts.setPitch(1.0);

    for (final tag in locale.fallbackTags) {
      try {
        final available = await _tts.isLanguageAvailable(tag);
        if (available == true || available == 1) {
          await _tts.setLanguage(tag);
          return;
        }
      } catch (_) {}
    }
    await _tts.setLanguage(locale.bcp47);
  }

  @override
  Future<void> speak(
    String text, {
    required void Function(double progressRatio) onProgress,
    required VoidCallback onComplete,
    required void Function(String error) onError,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      onComplete();
      return;
    }

    _ensureHandlers();
    // Prevent overlapping playback from prior turns.
    await _tts.stop();

    _onProgress = onProgress;
    _onComplete = onComplete;
    _onError = onError;

    try {
      final result = await _tts.speak(trimmed);
      if (result != 1) {
        onError('TTS engine did not start playback.');
      }
    } catch (e) {
      onError('TTS playback failed: $e');
    }
  }

  @override
  Future<void> stop() async {
    _onProgress = null;
    _onComplete = null;
    _onError = null;
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
