import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hey_dane/app/core/constants/app_identity.dart';
import 'package:hey_dane/app/core/theme/dane_colors.dart';
import 'package:hey_dane/app/features/chat/chat_controller.dart';
import 'package:hey_dane/app/shared/providers/app_state_provider.dart';
import 'package:hey_dane/app/shared/widgets/glass_surface.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    await ref.read(chatControllerProvider.notifier).sendPrompt(text);
  }

  @override
  Widget build(BuildContext context) {
    final turns = ref.watch(conversationTurnsProvider);
    final provider = ref.watch(activeProviderKindProvider);
    final models = ref.watch(selectedModelsProvider);
    final activeModel = models[provider] ?? provider.defaultModel;
    final isGenerating = ref.watch(chatControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat with Dane'),
        actions: [
          if (turns.isNotEmpty)
            IconButton(
              tooltip: 'Clear conversation',
              onPressed: () {
                ref.read(chatControllerProvider.notifier).clearHistory();
              },
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: turns.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: GlassSurface(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.forum_outlined,
                                size: 36,
                                color: DaneColors.cyanCore,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Start a conversation with ${AppIdentity.assistantName}',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Provider: ${provider.label} · $activeModel',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: turns.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final turn = turns[index];
                        return Align(
                          alignment: turn.isUser
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 560),
                            child: GlassSurface(
                              padding: const EdgeInsets.all(14),
                              borderRadius: 18,
                              borderColor: turn.isError
                                  ? DaneColors.alertCrimson.withValues(alpha: 0.7)
                                  : turn.isUser
                                      ? DaneColors.cyanCore.withValues(alpha: 0.4)
                                      : DaneColors.electricBlue.withValues(alpha: 0.35),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          turn.isUser
                                              ? 'You'
                                              : '${AppIdentity.assistantName} · ${turn.providerLabel ?? provider.label}'
                                                  '${turn.modelLabel != null ? " (${turn.modelLabel})" : ""}',
                                          overflow: TextOverflow.ellipsis,
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
                                      ),
                                      if (turn.text.isNotEmpty)
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          tooltip: 'Copy response',
                                          icon: const Icon(
                                            Icons.copy_rounded,
                                            size: 16,
                                          ),
                                          onPressed: () {
                                            Clipboard.setData(
                                              ClipboardData(text: turn.text),
                                            );
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text('Copied to clipboard'),
                                                duration: Duration(seconds: 2),
                                              ),
                                            );
                                          },
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    turn.text.isEmpty && turn.isStreaming
                                        ? 'Thinking...'
                                        : turn.text,
                                  ),
                                  if (turn.usage != null &&
                                      turn.usage!.totalTokens > 0) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'Tokens: ${turn.usage!.totalTokens} '
                                      '(in ${turn.usage!.promptTokens} / out ${turn.usage!.completionTokens})',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: DaneColors.textSecondaryDark,
                                          ),
                                    ),
                                  ],
                                  if (turn.isError &&
                                      turn.sourcePrompt != null &&
                                      !isGenerating) ...[
                                    const SizedBox(height: 8),
                                    TextButton.icon(
                                      onPressed: () => ref
                                          .read(chatControllerProvider.notifier)
                                          .retryTurn(turn),
                                      icon: const Icon(Icons.refresh_rounded, size: 16),
                                      label: const Text('Retry'),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: !isGenerating,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: const InputDecoration(
                        hintText: 'Message Dane...',
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
                      onPressed: _sendMessage,
                      tooltip: 'Send message',
                      icon: const Icon(Icons.send_rounded),
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
