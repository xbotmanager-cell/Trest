import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hey_dane/app/core/constants/app_identity.dart';
import 'package:hey_dane/app/core/theme/dane_colors.dart';
import 'package:hey_dane/app/features/chat/chat_controller.dart';
import 'package:hey_dane/app/features/hologram/widgets/holographic_orb.dart';
import 'package:hey_dane/app/shared/providers/app_state_provider.dart';
import 'package:hey_dane/app/shared/widgets/glass_surface.dart';

class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final TextEditingController _inputController = TextEditingController();

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  void _openLiveVoiceOrStop() {
    final isGenerating = ref.read(chatControllerProvider);
    if (isGenerating) {
      ref.read(chatControllerProvider.notifier).stopGeneration();
      return;
    }
    context.push('/live-voice');
  }

  Future<void> _submitTextPrompt() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _inputController.clear();
    await ref.read(chatControllerProvider.notifier).sendPrompt(text);
  }

  @override
  Widget build(BuildContext context) {
    final orbState = ref.watch(orbStateProvider);
    final voiceState = ref.watch(liveVoiceControllerProvider);
    final provider = ref.watch(activeProviderKindProvider);
    final models = ref.watch(selectedModelsProvider);
    final activeModel = models[provider] ?? provider.defaultModel;
    final turns = ref.watch(conversationTurnsProvider);
    final wakeEnabled = ref.watch(wakeWordEnabledProvider);
    final isGenerating = ref.watch(chatControllerProvider);
    final tokenUsage = ref.watch(sessionTokenUsageProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppIdentity.appName),
        actions: [
          TextButton.icon(
            onPressed: () => context.go('/settings'),
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: Text(provider.label),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 720;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      GlassSurface(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 24,
                        ),
                        child: Column(
                          children: [
                            HolographicOrb(
                              state: orbState,
                              audioLevel: voiceState.audioLevel,
                              size: isWide ? 236 : 204,
                              onTap: _openLiveVoiceOrStop,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              orbState == DaneOrbState.listening
                                  ? 'Listening for "${AppIdentity.wakePhrase}"...'
                                  : '${AppIdentity.assistantName} · ${orbState.statusLabel}',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Provider: ${provider.label} ($activeModel) · '
                              'Voice: ${voiceState.locale.displayName} · '
                              'Wake: ${wakeEnabled ? "Armed" : "Manual"} · '
                              'Tokens: ${tokenUsage.totalTokens}',
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: isDark
                                        ? DaneColors.textSecondaryDark
                                        : DaneColors.textSecondaryLight,
                                  ),
                            ),
                            const SizedBox(height: 20),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              alignment: WrapAlignment.center,
                              children: [
                                FilledButton.icon(
                                  onPressed: _openLiveVoiceOrStop,
                                  icon: Icon(
                                    isGenerating
                                        ? Icons.stop_rounded
                                        : Icons.graphic_eq_rounded,
                                  ),
                                  label: Text(
                                    isGenerating
                                        ? 'Stop Generation'
                                        : 'Activate Voice',
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () => context.go('/chat'),
                                  icon: const Icon(Icons.forum_outlined),
                                  label: const Text('Open Chat'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _inputController,
                              enabled: !isGenerating,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _submitTextPrompt(),
                              decoration: const InputDecoration(
                                hintText:
                                    'Ask Dane to analyze, draft, or plan a device action...',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          if (isGenerating)
                            IconButton.filled(
                              onPressed: () => ref
                                  .read(chatControllerProvider.notifier)
                                  .stopGeneration(),
                              tooltip: 'Stop generation',
                              icon: const Icon(Icons.stop_rounded),
                            )
                          else
                            IconButton.filled(
                              onPressed: _submitTextPrompt,
                              tooltip: 'Send prompt',
                              icon: const Icon(Icons.arrow_upward_rounded),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Quick Actions',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _QuickActionTile(
                            icon: Icons.security_rounded,
                            label: 'Permission Center',
                            onTap: () => context.go('/permissions'),
                          ),
                          _QuickActionTile(
                            icon: Icons.bolt_rounded,
                            label: 'Device Automation',
                            onTap: () => context.go('/automation'),
                          ),
                          _QuickActionTile(
                            icon: Icons.psychology_outlined,
                            label: 'Memory',
                            onTap: () => context.push('/memory'),
                          ),
                          _QuickActionTile(
                            icon: Icons.info_outline_rounded,
                            label: 'About Dane',
                            onTap: () => context.push('/about'),
                          ),
                        ],
                      ),
                      if (turns.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Text(
                          'Recent Conversation',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 10),
                        for (final turn in turns.reversed.take(4))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: GlassSurface(
                              padding: const EdgeInsets.all(14),
                              borderRadius: 16,
                              borderColor: turn.isError
                                  ? DaneColors.alertCrimson.withValues(alpha: 0.6)
                                  : null,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    turn.isUser
                                        ? 'You'
                                        : '${AppIdentity.assistantName} · ${turn.providerLabel ?? provider.label}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: turn.isError
                                              ? DaneColors.alertCrimson
                                              : turn.isUser
                                                  ? DaneColors.cyanCore
                                                  : DaneColors.electricBlue,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    turn.text.isEmpty && turn.isStreaming
                                        ? 'Thinking...'
                                        : turn.text,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: GlassSurface(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        borderRadius: 16,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: DaneColors.cyanCore),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
