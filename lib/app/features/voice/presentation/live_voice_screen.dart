import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hey_dane/app/core/constants/app_identity.dart';
import 'package:hey_dane/app/core/theme/dane_colors.dart';
import 'package:hey_dane/app/features/hologram/widgets/holographic_orb.dart';
import 'package:hey_dane/app/features/voice/domain/voice_models.dart';
import 'package:hey_dane/app/shared/providers/app_state_provider.dart';
import 'package:hey_dane/app/shared/widgets/glass_surface.dart';
import 'package:permission_handler/permission_handler.dart';

class LiveVoiceScreen extends ConsumerStatefulWidget {
  const LiveVoiceScreen({super.key});

  @override
  ConsumerState<LiveVoiceScreen> createState() => _LiveVoiceScreenState();
}

class _LiveVoiceScreenState extends ConsumerState<LiveVoiceScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) {
        ref.read(liveVoiceControllerProvider.notifier).startSession();
      }
    });
  }

  Future<void> _endConversation() async {
    await ref.read(liveVoiceControllerProvider.notifier).endSession();
    if (mounted) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final voiceState = ref.watch(liveVoiceControllerProvider);
    final controller = ref.read(liveVoiceControllerProvider.notifier);
    final provider = ref.watch(activeProviderKindProvider);
    final models = ref.watch(selectedModelsProvider);
    final activeModel = models[provider] ?? provider.defaultModel;

    final statusHint = switch (voiceState.orbState) {
      DaneOrbState.idle =>
        voiceState.isMicMuted ? 'Microphone muted · Tap orb or unmute' : 'Tap the orb to speak',
      DaneOrbState.listening => 'Listening · Speak naturally',
      DaneOrbState.thinking => 'Thinking via ${provider.label}...',
      DaneOrbState.speaking => 'Speaking · Tap orb to interrupt',
      DaneOrbState.error => 'Voice session needs attention',
    };

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_endConversation());
        }
      },
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.1),
              radius: 1.15,
              colors: [
                DaneColors.deepSpace,
                DaneColors.voidBlack,
              ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Column(
                children: [
                  // Top Bar
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '${AppIdentity.appName} Live',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: DaneColors.textPrimaryDark,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${provider.label} · $activeModel',
                            style: const TextStyle(
                              fontSize: 12,
                              color: DaneColors.textSecondaryDark,
                            ),
                          ),
                        ],
                      ),
                      SegmentedButton<VoiceLocaleOption>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: VoiceLocaleOption.english,
                            label: Text('EN'),
                          ),
                          ButtonSegment(
                            value: VoiceLocaleOption.swahili,
                            label: Text('SW'),
                          ),
                        ],
                        selected: {voiceState.locale},
                        onSelectionChanged: (selection) {
                          controller.setLocale(selection.first);
                        },
                      ),
                    ],
                  ),

                  const Spacer(),

                  // Center Gemini-Live-style Audio-Reactive Orb
                  HolographicOrb(
                    state: voiceState.orbState,
                    audioLevel: voiceState.audioLevel,
                    size: MediaQuery.sizeOf(context).shortestSide >= 600 ? 290 : 256,
                    onTap: () => controller.handleOrbTap(),
                  ),

                  const SizedBox(height: 18),

                  Text(
                    voiceState.orbState.statusLabel,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: DaneColors.textPrimaryDark,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    statusHint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      color: DaneColors.cyanCore,
                    ),
                  ),

                  const Spacer(),

                  // Live Transcription & Spoken Response Area
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640, maxHeight: 200),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (voiceState.errorMessage != null)
                            GlassSurface(
                              borderColor: DaneColors.alertCrimson.withValues(alpha: 0.7),
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    voiceState.errorMessage!,
                                    style: const TextStyle(
                                      color: DaneColors.textPrimaryDark,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 10,
                                    children: [
                                      FilledButton.tonal(
                                        onPressed: controller.retryAfterError,
                                        child: const Text('Retry'),
                                      ),
                                      OutlinedButton(
                                        onPressed: controller.returnToIdle,
                                        child: const Text('Idle'),
                                      ),
                                      OutlinedButton(
                                        onPressed: openAppSettings,
                                        child: const Text('App Settings'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            )
                          else if (voiceState.liveTranscript.isNotEmpty ||
                              voiceState.assistantResponse.isNotEmpty)
                            GlassSurface(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (voiceState.liveTranscript.isNotEmpty) ...[
                                    const Text(
                                      'You',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: DaneColors.cyanCore,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      voiceState.liveTranscript,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: DaneColors.textPrimaryDark,
                                      ),
                                    ),
                                  ],
                                  if (voiceState.liveTranscript.isNotEmpty &&
                                      voiceState.assistantResponse.isNotEmpty)
                                    const SizedBox(height: 10),
                                  if (voiceState.assistantResponse.isNotEmpty) ...[
                                    const Text(
                                      AppIdentity.assistantName,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: DaneColors.electricBlue,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      voiceState.assistantResponse,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: DaneColors.textPrimaryDark,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Bottom Ergonomic Control Dock
                  GlassSurface(
                    borderRadius: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        IconButton.filledTonal(
                          tooltip: voiceState.isMicMuted ? 'Unmute microphone' : 'Mute microphone',
                          onPressed: controller.toggleMicMute,
                          icon: Icon(
                            voiceState.isMicMuted
                                ? Icons.mic_off_rounded
                                : Icons.mic_rounded,
                          ),
                        ),
                        IconButton.filledTonal(
                          tooltip: voiceState.isSpeakerMuted
                              ? 'Unmute speaker'
                              : 'Mute speaker',
                          onPressed: controller.toggleSpeakerMute,
                          icon: Icon(
                            voiceState.isSpeakerMuted
                                ? Icons.volume_off_rounded
                                : Icons.volume_up_rounded,
                          ),
                        ),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: DaneColors.alertCrimson,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _endConversation,
                          icon: const Icon(Icons.call_end_rounded),
                          label: const Text('End'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
