import 'package:hey_dane/app/shared/providers/app_state_provider.dart';

enum VoiceLocaleOption {
  english('en-US', 'English', ['en-US', 'en-GB', 'en']),
  swahili('sw-KE', 'Swahili', ['sw-KE', 'sw-TZ', 'sw']);

  const VoiceLocaleOption(this.bcp47, this.displayName, this.fallbackTags);
  final String bcp47;
  final String displayName;
  final List<String> fallbackTags;
}

class VoiceSessionState {
  const VoiceSessionState({
    this.orbState = DaneOrbState.idle,
    this.isSessionActive = false,
    this.isMicMuted = false,
    this.isSpeakerMuted = false,
    this.audioLevel = 0.0,
    this.liveTranscript = '',
    this.assistantResponse = '',
    this.errorMessage,
    this.locale = VoiceLocaleOption.english,
    this.wakeWordArmed = false,
    this.wakeWordStatusNote = 'Manual voice activation ready',
    this.speechRate = 0.5,
  });

  final DaneOrbState orbState;
  final bool isSessionActive;
  final bool isMicMuted;
  final bool isSpeakerMuted;
  final double audioLevel;
  final String liveTranscript;
  final String assistantResponse;
  final String? errorMessage;
  final VoiceLocaleOption locale;
  final bool wakeWordArmed;
  final String wakeWordStatusNote;
  final double speechRate;

  VoiceSessionState copyWith({
    DaneOrbState? orbState,
    bool? isSessionActive,
    bool? isMicMuted,
    bool? isSpeakerMuted,
    double? audioLevel,
    String? liveTranscript,
    String? assistantResponse,
    String? errorMessage,
    bool clearError = false,
    VoiceLocaleOption? locale,
    bool? wakeWordArmed,
    String? wakeWordStatusNote,
    double? speechRate,
  }) {
    return VoiceSessionState(
      orbState: orbState ?? this.orbState,
      isSessionActive: isSessionActive ?? this.isSessionActive,
      isMicMuted: isMicMuted ?? this.isMicMuted,
      isSpeakerMuted: isSpeakerMuted ?? this.isSpeakerMuted,
      audioLevel: audioLevel ?? this.audioLevel,
      liveTranscript: liveTranscript ?? this.liveTranscript,
      assistantResponse: assistantResponse ?? this.assistantResponse,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      locale: locale ?? this.locale,
      wakeWordArmed: wakeWordArmed ?? this.wakeWordArmed,
      wakeWordStatusNote: wakeWordStatusNote ?? this.wakeWordStatusNote,
      speechRate: speechRate ?? this.speechRate,
    );
  }
}
