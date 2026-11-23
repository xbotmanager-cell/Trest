import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hey_dane/app/core/constants/app_identity.dart';
import 'package:hey_dane/app/core/theme/dane_colors.dart';
import 'package:hey_dane/app/features/voice/domain/voice_models.dart';
import 'package:hey_dane/app/shared/providers/app_state_provider.dart';
import 'package:hey_dane/app/shared/widgets/glass_surface.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final TextEditingController _proxyController = TextEditingController();
  final Map<AiProviderKind, TextEditingController> _keyControllers = {
    for (final k in AiProviderKind.values) k: TextEditingController(),
  };
  final Map<AiProviderKind, bool> _savedKeyFlags = {};
  final Map<AiProviderKind, bool> _testingFlags = {};

  @override
  void initState() {
    super.initState();
    _loadVaultState();
  }

  @override
  void dispose() {
    _proxyController.dispose();
    for (final c in _keyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadVaultState() async {
    final vault = ref.read(keyVaultProvider);
    final proxy = await vault.readProxyBaseUrl();
    final flags = <AiProviderKind, bool>{};
    for (final kind in AiProviderKind.values) {
      final key = await vault.readKey(kind);
      flags[kind] = key != null && key.isNotEmpty;
    }
    if (!mounted) return;
    setState(() {
      _proxyController.text = proxy ?? '';
      _savedKeyFlags
        ..clear()
        ..addAll(flags);
    });
  }

  Future<void> _saveProxyUrl() async {
    final vault = ref.read(keyVaultProvider);
    await vault.writeProxyBaseUrl(_proxyController.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Backend proxy URL updated securely.')),
    );
  }

  Future<void> _saveProviderKey(AiProviderKind kind) async {
    final vault = ref.read(keyVaultProvider);
    final controller = _keyControllers[kind]!;
    await vault.writeKey(kind, controller.text);
    controller.clear();
    await _loadVaultState();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('${kind.label} key stored in encrypted Keystore.')),
    );
  }

  Future<void> _clearProviderKey(AiProviderKind kind) async {
    final vault = ref.read(keyVaultProvider);
    await vault.deleteKey(kind);
    await _loadVaultState();
  }

  Future<void> _testProviderConnection(AiProviderKind kind) async {
    setState(() => _testingFlags[kind] = true);
    final router = ref.read(aiRouterServiceProvider);
    final models = ref.read(selectedModelsProvider);
    final model = models[kind] ?? kind.defaultModel;
    final status = await router.testProvider(kind: kind, model: model);
    if (!mounted) return;
    final updated = Map.of(ref.read(providerStatusesProvider))..[kind] = status;
    ref.read(providerStatusesProvider.notifier).state = updated;
    setState(() => _testingFlags[kind] = false);
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final activeProvider = ref.watch(activeProviderKindProvider);
    final selectedModels = ref.watch(selectedModelsProvider);
    final fallbackEnabled = ref.watch(openRouterFallbackProvider);
    final wakeWordEnabled = ref.watch(wakeWordEnabledProvider);
    final providerStatuses = ref.watch(providerStatusesProvider);
    final providersMap = ref.watch(aiProvidersMapProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('AI & System Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            GlassSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Production Backend Proxy',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Use a server-side proxy URL for production Gemini credentials so no production secret is ever embedded in the APK.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _proxyController,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(
                            hintText: 'https://your-dane-proxy.run.app',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.tonal(
                        onPressed: _saveProxyUrl,
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Default AI Provider',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 10),
            RadioGroup<AiProviderKind>(
              groupValue: activeProvider,
              onChanged: (value) {
                if (value != null) {
                  ref.read(activeProviderKindProvider.notifier).state = value;
                }
              },
              child: Column(
                children: [
                  for (final kind in AiProviderKind.values) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: GlassSurface(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Radio<AiProviderKind>(value: kind),
                                Expanded(
                                  child: Text(
                                    '${kind.label} Provider',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Text(
                                  _savedKeyFlags[kind] == true
                                      ? 'Key Stored'
                                      : 'No Dev Key',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _savedKeyFlags[kind] == true
                                        ? DaneColors.nominalGreen
                                        : DaneColors.textSecondaryDark,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                key: ValueKey(
                                  '${kind.name}_${selectedModels[kind] ?? kind.defaultModel}',
                                ),
                                initialValue:
                                    selectedModels[kind] ?? kind.defaultModel,
                                decoration:
                                    const InputDecoration(labelText: 'Model'),
                                items: [
                                  for (final m
                                      in providersMap[kind]!.availableModels)
                                    DropdownMenuItem(value: m, child: Text(m)),
                                ],
                                onChanged: (value) {
                                  if (value == null) return;
                                  final next = Map.of(selectedModels)
                                    ..[kind] = value;
                                  ref
                                      .read(selectedModelsProvider.notifier)
                                      .state = next;
                                },
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _keyControllers[kind],
                                    obscureText: true,
                                    enableSuggestions: false,
                                    autocorrect: false,
                                    decoration: InputDecoration(
                                      hintText: _savedKeyFlags[kind] == true
                                          ? 'Replace stored dev API key...'
                                          : 'Enter dev ${kind.label} API key...',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FilledButton.tonal(
                                  onPressed: () => _saveProviderKey(kind),
                                  child: const Text('Save'),
                                ),
                                if (_savedKeyFlags[kind] == true) ...[
                                  const SizedBox(width: 6),
                                  IconButton(
                                    tooltip: 'Remove stored key',
                                    onPressed: () => _clearProviderKey(kind),
                                    icon: const Icon(
                                        Icons.delete_outline_rounded),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _testingFlags[kind] == true
                                      ? null
                                      : () => _testProviderConnection(kind),
                                  icon: _testingFlags[kind] == true
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        )
                                      : const Icon(Icons.network_check_rounded,
                                          size: 18),
                                  label: const Text('Test Connection'),
                                ),
                                const SizedBox(width: 12),
                                if (providerStatuses[kind] != null)
                                  Expanded(
                                    child: Text(
                                      providerStatuses[kind]!.detail,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: providerStatuses[kind]!.reachable
                                            ? DaneColors.nominalGreen
                                            : DaneColors.alertCrimson,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            GlassSurface(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('OpenRouter Automatic Fallback'),
                subtitle: const Text(
                  'Automatically route to OpenRouter when the primary provider fails and an OpenRouter key is stored.',
                ),
                value: fallbackEnabled,
                onChanged: (value) {
                  ref.read(openRouterFallbackProvider.notifier).state = value;
                },
              ),
            ),
            const SizedBox(height: 16),
            GlassSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Appearance',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text('Dark'),
                        icon: Icon(Icons.dark_mode_outlined),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text('Light'),
                        icon: Icon(Icons.light_mode_outlined),
                      ),
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text('System'),
                        icon: Icon(Icons.brightness_auto_outlined),
                      ),
                    ],
                    selected: {themeMode},
                    onSelectionChanged: (selection) {
                      ref.read(themeModeProvider.notifier).state =
                          selection.first;
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            GlassSurface(
              child: Builder(
                builder: (context) {
                  final voiceState = ref.watch(liveVoiceControllerProvider);
                  final voiceController =
                      ref.read(liveVoiceControllerProvider.notifier);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Voice & Speech Engine',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                      const SizedBox(height: 10),
                      SegmentedButton<VoiceLocaleOption>(
                        segments: const [
                          ButtonSegment(
                            value: VoiceLocaleOption.english,
                            label: Text('English'),
                          ),
                          ButtonSegment(
                            value: VoiceLocaleOption.swahili,
                            label: Text('Swahili'),
                          ),
                        ],
                        selected: {voiceState.locale},
                        onSelectionChanged: (selection) {
                          voiceController.setLocale(selection.first);
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Speech Rate: ${voiceState.speechRate.toStringAsFixed(2)}x',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Slider(
                        min: 0.25,
                        max: 0.85,
                        divisions: 12,
                        value: voiceState.speechRate,
                        onChanged: (v) => voiceController.setSpeechRate(v),
                      ),
                      const Divider(height: 16),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                            'Wake Phrase ("${AppIdentity.wakePhrase}")'),
                        subtitle: Text(voiceState.wakeWordStatusNote),
                        value: wakeWordEnabled,
                        onChanged: (value) async {
                          await voiceController.toggleWakeWord(
                            value,
                            onTriggered: () {
                              if (context.mounted) {
                                context.push('/live-voice');
                              }
                            },
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            GlassSurface(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.psychology_outlined),
                    title: const Text('Conversation Memory'),
                    subtitle: const Text('Review or clear stored preferences'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push('/memory'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.info_outline_rounded),
                    title: const Text('About Dane'),
                    subtitle: const Text('Version, device bridge & privacy'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push('/about'),
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
