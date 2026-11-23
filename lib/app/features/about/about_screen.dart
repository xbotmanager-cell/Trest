import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hey_dane/app/core/constants/app_identity.dart';
import 'package:hey_dane/app/core/theme/dane_colors.dart';
import 'package:hey_dane/app/features/hologram/widgets/holographic_d_logo.dart';
import 'package:hey_dane/app/shared/providers/app_state_provider.dart';
import 'package:hey_dane/app/shared/widgets/glass_surface.dart';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  Future<void> _toggleForegroundVoiceService(
    BuildContext context,
    WidgetRef ref,
    bool currentlyRunning,
  ) async {
    final platform = ref.read(nativePlatformServiceProvider);
    final ok = currentlyRunning
        ? await platform.stopVoiceForegroundService()
        : await platform.startVoiceForegroundService();

    if (!context.mounted) return;
    if (ok) {
      ref.read(foregroundVoiceServiceRunningProvider.notifier).state =
          !currentlyRunning;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            !currentlyRunning
                ? 'Foreground voice notification service started.'
                : 'Foreground voice notification service stopped.',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Foreground voice service requires an Android device with microphone and notification permissions.',
          ),
        ),
      );
    }
  }

  Future<void> _clearAllEncryptedData(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Encrypted Data?'),
        content: const Text(
          'This removes all locally stored API keys, saved memory preferences, session conversation history, and automation history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: DaneColors.alertCrimson,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear Everything'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(memoryVaultProvider).clearAll();
    final keyVault = ref.read(keyVaultProvider);
    for (final kind in AiProviderKind.values) {
      await keyVault.deleteKey(kind);
    }

    ref.read(memoryPreferencesProvider.notifier).state = const [];
    ref.read(conversationTurnsProvider.notifier).state = const [];
    ref.read(pendingActionsProvider.notifier).state = const [];
    ref.read(automationHistoryProvider.notifier).state = const [];

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cleared all local encrypted data.')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(deviceSnapshotProvider);
    final fgsRunning = ref.watch(foregroundVoiceServiceRunningProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('About & Privacy')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            GlassSurface(
              child: Column(
                children: [
                  const HolographicDLogo(size: 84),
                  const SizedBox(height: 14),
                  const Text(
                    AppIdentity.appName,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(AppIdentity.tagline),
                  const SizedBox(height: 8),
                  Text(
                    'Version ${AppIdentity.version} (${AppIdentity.buildNumber}) · ${AppIdentity.packageId}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            GlassSurface(
              child: snapshotAsync.when(
                data: (device) {
                  final bootLabel = device.lastBootMs > 0
                      ? DateTime.fromMillisecondsSinceEpoch(device.lastBootMs)
                          .toLocal()
                          .toString()
                      : 'No boot broadcast recorded since install';
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Native Android Platform Bridge',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text('Device: ${device.manufacturer} ${device.model}'),
                      Text(
                        'Android Release: ${device.androidRelease} (API ${device.sdkInt})',
                      ),
                      Text(
                        'Kotlin Channel: ${device.isNativeConnected ? "Connected" : "Unavailable on current host"}',
                      ),
                      Text('Boot Receiver Timestamp: $bootLabel'),
                    ],
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => const Text('Unable to query native device info.'),
              ),
            ),
            const SizedBox(height: 16),
            GlassSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Locked-Screen & Foreground Voice Mode',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Android 14+ restricts silent background microphone capture and automatic boot-time mic services. HEY DANE uses an explicit foreground service with a persistent notification and Stop action whenever locked-screen voice mode is active.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: () =>
                        _toggleForegroundVoiceService(context, ref, fgsRunning),
                    icon: Icon(
                      fgsRunning
                          ? Icons.stop_circle_outlined
                          : Icons.notifications_active_outlined,
                    ),
                    label: Text(
                      fgsRunning
                          ? 'Stop Foreground Voice Service'
                          : 'Start Foreground Voice Service',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            GlassSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Privacy Policy & Data Controls',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '• No hidden microphone surveillance or silent privilege elevation.\n'
                    '• API keys and saved preferences stay in encrypted Android Keystore storage.\n'
                    '• Only explicit user prompts are sent to your chosen AI provider.\n'
                    '• Medium and high-risk device actions require explicit user confirmation.',
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: DaneColors.alertCrimson,
                      side: const BorderSide(color: DaneColors.alertCrimson),
                    ),
                    onPressed: () => _clearAllEncryptedData(context, ref),
                    icon: const Icon(Icons.delete_forever_outlined),
                    label: const Text('Clear All Encrypted Data'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
