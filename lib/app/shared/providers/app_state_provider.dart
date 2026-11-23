import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hey_dane/app/core/security/secure_key_vault.dart';
import 'package:hey_dane/app/features/alarms/alarm_service.dart';
import 'package:hey_dane/app/features/automation/domain/dane_action.dart';
import 'package:hey_dane/app/features/automation/services/action_engine.dart';
import 'package:hey_dane/app/features/calls/call_service.dart';
import 'package:hey_dane/app/features/files/file_service.dart';
import 'package:hey_dane/app/features/memory/services/memory_vault.dart';
import 'package:hey_dane/app/features/messages/messaging_service.dart';
import 'package:hey_dane/app/features/permissions/services/permission_center_service.dart';
import 'package:hey_dane/app/features/providers/domain/ai_models.dart';
import 'package:hey_dane/app/features/providers/domain/ai_provider.dart';
import 'package:hey_dane/app/features/providers/gemini/gemini_provider.dart';
import 'package:hey_dane/app/features/providers/groq/groq_provider.dart';
import 'package:hey_dane/app/features/providers/openrouter/openrouter_provider.dart';
import 'package:hey_dane/app/features/providers/services/ai_preferences_store.dart';
import 'package:hey_dane/app/features/providers/services/ai_router_service.dart';
import 'package:hey_dane/app/features/voice/controllers/live_voice_controller.dart';
import 'package:hey_dane/app/features/voice/domain/voice_models.dart';
import 'package:hey_dane/app/features/voice/services/speech_recognition_service.dart';
import 'package:hey_dane/app/features/voice/services/tts_service.dart';
import 'package:hey_dane/app/features/voice/services/wake_word_service.dart';
import 'package:hey_dane/app/shared/services/native_platform_service.dart';

enum AiProviderKind {
  gemini('Gemini', 'gemini-4-hydrogen'),
  groq('Groq', 'llama-3.3-70b-versatile'),
  openRouter('OpenRouter', 'anthropic/claude-3.5-sonnet');

  const AiProviderKind(this.label, this.defaultModel);
  final String label;
  final String defaultModel;
}

enum DaneOrbState {
  idle('Ready'),
  listening('Listening'),
  thinking('Thinking'),
  speaking('Speaking'),
  error('Attention Needed');

  const DaneOrbState(this.statusLabel);
  final String statusLabel;
}

class ChatTurn {
  const ChatTurn({
    required this.id,
    required this.isUser,
    required this.text,
    required this.timestamp,
    this.providerLabel,
    this.modelLabel,
    this.isError = false,
    this.isStreaming = false,
    this.usage,
    this.sourcePrompt,
  });

  final String id;
  final bool isUser;
  final String text;
  final DateTime timestamp;
  final String? providerLabel;
  final String? modelLabel;
  final bool isError;
  final bool isStreaming;
  final TokenUsage? usage;
  final String? sourcePrompt;

  ChatTurn copyWith({
    String? text,
    String? providerLabel,
    String? modelLabel,
    bool? isError,
    bool? isStreaming,
    TokenUsage? usage,
  }) {
    return ChatTurn(
      id: id,
      isUser: isUser,
      text: text ?? this.text,
      timestamp: timestamp,
      providerLabel: providerLabel ?? this.providerLabel,
      modelLabel: modelLabel ?? this.modelLabel,
      isError: isError ?? this.isError,
      isStreaming: isStreaming ?? this.isStreaming,
      usage: usage ?? this.usage,
      sourcePrompt: sourcePrompt,
    );
  }
}

final nativePlatformServiceProvider = Provider<NativePlatformService>((ref) {
  return NativePlatformService();
});

final keyVaultProvider = Provider<KeyVaultStore>((ref) {
  return SecureKeyVault();
});

final aiProvidersMapProvider = Provider<Map<AiProviderKind, AiProvider>>((ref) {
  return {
    AiProviderKind.gemini: GeminiProvider(),
    AiProviderKind.groq: GroqProvider(),
    AiProviderKind.openRouter: OpenRouterProvider(),
  };
});

final aiRouterServiceProvider = Provider<AiRouterService>((ref) {
  return AiRouterService(
    providers: ref.watch(aiProvidersMapProvider),
    keyVault: ref.watch(keyVaultProvider),
  );
});

final speechRecognitionAdapterProvider =
    Provider<SpeechRecognitionAdapter>((ref) {
  return DeviceSpeechRecognitionAdapter();
});

final ttsAdapterProvider = Provider<TtsAdapter>((ref) {
  return DeviceTtsAdapter();
});

final wakeWordEngineProvider = Provider<WakeWordEngine>((ref) {
  return ForegroundPhraseWakeWordEngine(
    speechAdapter: ref.watch(speechRecognitionAdapterProvider),
  );
});

final liveVoiceControllerProvider =
    StateNotifierProvider<LiveVoiceController, VoiceSessionState>((ref) {
  return LiveVoiceController(
    ref: ref,
    speechAdapter: ref.watch(speechRecognitionAdapterProvider),
    ttsAdapter: ref.watch(ttsAdapterProvider),
    wakeWordEngine: ref.watch(wakeWordEngineProvider),
  );
});

final deviceSnapshotProvider =
    FutureProvider<AndroidDeviceSnapshot>((ref) async {
  final service = ref.watch(nativePlatformServiceProvider);
  return service.getDeviceSnapshot();
});

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.dark);

final activeProviderKindProvider = StateProvider<AiProviderKind>(
  (ref) => AiProviderKind.gemini,
);

final selectedModelsProvider = StateProvider<Map<AiProviderKind, String>>(
  (ref) => {
    AiProviderKind.gemini: AiProviderKind.gemini.defaultModel,
    AiProviderKind.groq: AiProviderKind.groq.defaultModel,
    AiProviderKind.openRouter: AiProviderKind.openRouter.defaultModel,
  },
);

final openRouterFallbackProvider = StateProvider<bool>((ref) => true);

final fallbackOrderProvider = StateProvider<List<AiProviderKind>>(
  (ref) => const [
    AiProviderKind.openRouter,
    AiProviderKind.groq,
    AiProviderKind.gemini,
  ],
);

final aiPreferencesStoreProvider = Provider<AiPreferencesStore>((ref) {
  return SharedPrefsAiPreferencesStore();
});

final providerStatusesProvider =
    StateProvider<Map<AiProviderKind, ProviderConnectionStatus>>(
        (ref) => const {});

final sessionTokenUsageProvider = StateProvider<TokenUsage>(
  (ref) => const TokenUsage(),
);

final orbStateProvider = StateProvider<DaneOrbState>(
  (ref) => DaneOrbState.idle,
);

final wakeWordEnabledProvider = StateProvider<bool>((ref) => false);

final conversationTurnsProvider = StateProvider<List<ChatTurn>>(
  (ref) => const <ChatTurn>[],
);

final permissionCenterServiceProvider =
    Provider<PermissionCenterService>((ref) {
  return PermissionCenterService();
});

final actionEngineProvider = Provider<ActionEngine>((ref) {
  return ActionEngine();
});

final alarmServiceProvider = Provider<AlarmService>((ref) {
  return AlarmService(ref.watch(actionEngineProvider));
});

final callServiceProvider = Provider<CallService>((ref) {
  return CallService(ref.watch(actionEngineProvider));
});

final messagingServiceProvider = Provider<MessagingService>((ref) {
  return MessagingService(ref.watch(actionEngineProvider));
});

final fileServiceProvider = Provider<FileService>((ref) {
  return FileService(ref.watch(actionEngineProvider));
});

final memoryVaultProvider = Provider<MemoryStore>((ref) {
  return EncryptedMemoryVault();
});

final automationFeatureFlagsProvider = StateProvider<AutomationFeatureFlags>(
  (ref) => const AutomationFeatureFlags(),
);

final pendingActionsProvider = StateProvider<List<DaneAction>>(
  (ref) => const <DaneAction>[],
);

final automationHistoryProvider = StateProvider<List<DaneAction>>(
  (ref) => const <DaneAction>[],
);

final memoryPreferencesProvider = StateProvider<List<MemoryRecord>>(
  (ref) => const <MemoryRecord>[],
);

final foregroundVoiceServiceRunningProvider = StateProvider<bool>(
  (ref) => false,
);
