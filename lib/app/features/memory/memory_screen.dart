import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hey_dane/app/core/theme/dane_colors.dart';
import 'package:hey_dane/app/features/memory/services/memory_vault.dart';
import 'package:hey_dane/app/shared/providers/app_state_provider.dart';
import 'package:hey_dane/app/shared/widgets/glass_surface.dart';
import 'package:uuid/uuid.dart';

class MemoryScreen extends ConsumerStatefulWidget {
  const MemoryScreen({super.key});

  @override
  ConsumerState<MemoryScreen> createState() => _MemoryScreenState();
}

class _MemoryScreenState extends ConsumerState<MemoryScreen> {
  final Uuid _uuid = const Uuid();
  bool _loadingVault = true;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadFromVault);
  }

  Future<void> _loadFromVault() async {
    if (!_loadingVault && mounted) {
      setState(() => _loadingVault = true);
    }
    try {
      final records = await ref.read(memoryVaultProvider).loadPreferences();
      if (!mounted) return;
      ref.read(memoryPreferencesProvider.notifier).state = records;
    } catch (_) {
      // Encrypted storage may be unavailable on unsupported host platforms.
    } finally {
      if (mounted) {
        setState(() => _loadingVault = false);
      }
    }
  }

  Future<void> _addPreference() async {
    final labelController = TextEditingController();
    final valueController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save Encrypted Preference'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: labelController,
              decoration: const InputDecoration(
                labelText: 'Preference label',
                hintText: 'e.g. Response Style',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: valueController,
              decoration: const InputDecoration(
                labelText: 'Value',
                hintText: 'e.g. Concise English & Swahili',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final label = labelController.text.trim();
    final value = valueController.text.trim();
    labelController.dispose();
    valueController.dispose();
    if (confirmed != true || label.isEmpty || value.isEmpty) return;

    final current = ref.read(memoryPreferencesProvider);
    final updated = [
      MemoryRecord(
        id: _uuid.v4(),
        label: label,
        value: value,
        savedAt: DateTime.now(),
      ),
      ...current,
    ];
    await ref.read(memoryVaultProvider).savePreferences(updated);
    if (!mounted) return;
    ref.read(memoryPreferencesProvider.notifier).state = updated;
  }

  Future<void> _deletePreference(String id) async {
    final current = ref.read(memoryPreferencesProvider);
    final updated = current.where((r) => r.id != id).toList();
    await ref.read(memoryVaultProvider).savePreferences(updated);
    if (!mounted) return;
    ref.read(memoryPreferencesProvider.notifier).state = updated;
  }

  Future<void> _clearMemoryVault() async {
    await ref.read(memoryVaultProvider).clearAll();
    if (!mounted) return;
    ref.read(memoryPreferencesProvider.notifier).state = const [];
  }

  @override
  Widget build(BuildContext context) {
    final turns = ref.watch(conversationTurnsProvider);
    final preferences = ref.watch(memoryPreferencesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Memory & History'),
        actions: [
          if (turns.isNotEmpty)
            TextButton(
              onPressed: () {
                ref.read(conversationTurnsProvider.notifier).state = const [];
              },
              child: const Text('Clear Chat'),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            GlassSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Encrypted Memory Vault',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _addPreference,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _loadingVault
                        ? 'Loading encrypted preference records...'
                        : '${preferences.length} saved user-approved preferences · ${turns.length} active session turns.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (preferences.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _clearMemoryVault,
                        child: const Text(
                          'Wipe Saved Preferences',
                          style: TextStyle(color: DaneColors.alertCrimson),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (preferences.isNotEmpty) ...[
              Text(
                'Saved Preferences',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              for (final record in preferences)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GlassSurface(
                    padding: const EdgeInsets.all(14),
                    borderRadius: 16,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                record.label,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: DaneColors.cyanCore,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(record.value),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Delete preference',
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () => _deletePreference(record.id),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 10),
            ],
            Text(
              'Conversation History (${turns.length})',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            if (turns.isEmpty)
              GlassSurface(
                padding: const EdgeInsets.all(14),
                child: Text(
                  'No active conversation turns stored in this session.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else
              for (final turn in turns)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GlassSurface(
                    padding: const EdgeInsets.all(14),
                    borderRadius: 16,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                turn.isUser ? 'User Prompt' : 'Dane Response',
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                              const SizedBox(height: 4),
                              Text(turn.text),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Delete record',
                          icon: const Icon(Icons.delete_outline_rounded),
                          onPressed: () {
                            ref.read(conversationTurnsProvider.notifier).state =
                                turns.where((t) => t.id != turn.id).toList();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
