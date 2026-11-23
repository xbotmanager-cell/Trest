import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hey_dane/app/core/errors/ai_exception.dart';
import 'package:hey_dane/app/features/providers/domain/ai_models.dart';
import 'package:hey_dane/app/shared/providers/app_state_provider.dart';
import 'package:uuid/uuid.dart';

class ChatController extends StateNotifier<bool> {
  ChatController(this._ref) : super(false);

  final Ref _ref;
  final Uuid _uuid = const Uuid();
  CancellationToken? _activeCancellation;

  bool get isGenerating => state;

  Future<void> sendPrompt(String rawPrompt) async {
    final prompt = rawPrompt.trim();
    if (prompt.isEmpty || state) return;

    final providerKind = _ref.read(activeProviderKindProvider);
    final selectedModels = _ref.read(selectedModelsProvider);
    final model = selectedModels[providerKind] ?? providerKind.defaultModel;
    final allowFallback = _ref.read(openRouterFallbackProvider);
    final fallbackOrder = _ref.read(fallbackOrderProvider);
    final fallbackModel = selectedModels[AiProviderKind.openRouter];

    final existingTurns = _ref.read(conversationTurnsProvider);
    final history = existingTurns
        .where((t) => !t.isError && t.text.trim().isNotEmpty)
        .map((t) => AiMessageInput(role: t.isUser ? 'user' : 'assistant', text: t.text))
        .toList();

    final userTurn = ChatTurn(
      id: _uuid.v4(),
      isUser: true,
      text: prompt,
      timestamp: DateTime.now(),
    );
    final assistantId = _uuid.v4();
    final placeholderTurn = ChatTurn(
      id: assistantId,
      isUser: false,
      text: '',
      timestamp: DateTime.now(),
      providerLabel: providerKind.label,
      modelLabel: model,
      isStreaming: true,
      sourcePrompt: prompt,
    );

    _ref.read(conversationTurnsProvider.notifier).state = [
      ...existingTurns,
      userTurn,
      placeholderTurn,
    ];
    _ref.read(orbStateProvider.notifier).state = DaneOrbState.thinking;
    state = true;

    await _runStreamingTurn(
      assistantId: assistantId,
      prompt: prompt,
      history: history,
      providerKind: providerKind,
      model: model,
      allowFallback: allowFallback,
      fallbackOrder: fallbackOrder,
      selectedModels: selectedModels,
      fallbackModel: fallbackModel,
    );
  }

  Future<void> retryTurn(ChatTurn failedTurn) async {
    final prompt = failedTurn.sourcePrompt?.trim();
    if (prompt == null || prompt.isEmpty || state) return;

    final providerKind = _ref.read(activeProviderKindProvider);
    final selectedModels = _ref.read(selectedModelsProvider);
    final model = selectedModels[providerKind] ?? providerKind.defaultModel;
    final allowFallback = _ref.read(openRouterFallbackProvider);
    final fallbackOrder = _ref.read(fallbackOrderProvider);
    final fallbackModel = selectedModels[AiProviderKind.openRouter];

    final allTurns = _ref.read(conversationTurnsProvider);
    final idx = allTurns.indexWhere((t) => t.id == failedTurn.id);
    if (idx == -1) return;

    final history = allTurns
        .take(idx)
        .where((t) => !t.isError && t.text.trim().isNotEmpty)
        .map((t) => AiMessageInput(role: t.isUser ? 'user' : 'assistant', text: t.text))
        .toList();

    final updated = List<ChatTurn>.from(allTurns);
    updated[idx] = failedTurn.copyWith(
      text: '',
      isError: false,
      isStreaming: true,
      providerLabel: providerKind.label,
      modelLabel: model,
    );
    _ref.read(conversationTurnsProvider.notifier).state = updated;
    _ref.read(orbStateProvider.notifier).state = DaneOrbState.thinking;
    state = true;

    await _runStreamingTurn(
      assistantId: failedTurn.id,
      prompt: prompt,
      history: history,
      providerKind: providerKind,
      model: model,
      allowFallback: allowFallback,
      fallbackOrder: fallbackOrder,
      selectedModels: selectedModels,
      fallbackModel: fallbackModel,
    );
  }

  void stopGeneration() {
    _activeCancellation?.cancel();
    _activeCancellation = null;
    state = false;
    _ref.read(orbStateProvider.notifier).state = DaneOrbState.idle;

    final turns = _ref.read(conversationTurnsProvider);
    _ref.read(conversationTurnsProvider.notifier).state = [
      for (final t in turns)
        if (t.isStreaming)
          t.copyWith(
            isStreaming: false,
            text: t.text.isEmpty ? 'Generation stopped.' : t.text,
          )
        else
          t,
    ];
  }

  void clearHistory() {
    if (state) stopGeneration();
    _ref.read(conversationTurnsProvider.notifier).state = const [];
  }

  Future<void> _runStreamingTurn({
    required String assistantId,
    required String prompt,
    required List<AiMessageInput> history,
    required AiProviderKind providerKind,
    required String model,
    required bool allowFallback,
    required List<AiProviderKind> fallbackOrder,
    required Map<AiProviderKind, String> selectedModels,
    required String? fallbackModel,
  }) async {
    final cancellation = CancellationToken();
    _activeCancellation = cancellation;

    final router = _ref.read(aiRouterServiceProvider);
    final buffer = StringBuffer();
    TokenUsage? latestUsage;
    var activeLabel = providerKind.label;
    var activeModel = model;

    try {
      await for (final event in router.streamWithFallback(
        primaryKind: providerKind,
        primaryModel: model,
        allowOpenRouterFallback: allowFallback,
        fallbackOrder: fallbackOrder,
        selectedModels: selectedModels,
        openRouterFallbackModel: fallbackModel,
        cancellationToken: cancellation,
        request: AiRequest(
          prompt: prompt,
          model: model,
          history: history,
          systemInstruction:
              'You are Dane, the personal AI assistant in HEY DANE (Your Personal AI. Your Digital Power.). '
              'Respond clearly, concisely, and accurately. Never claim to have performed device actions without verified execution results.',
        ),
      )) {
        if (cancellation.isCancelled) break;

        activeLabel = event.usedFallback
            ? '${event.providerUsed.label} (Fallback)'
            : event.providerUsed.label;
        activeModel = event.modelUsed;

        if (event.delta.textDelta.isNotEmpty) {
          buffer.write(event.delta.textDelta);
          _ref.read(orbStateProvider.notifier).state = DaneOrbState.speaking;
        }
        if (event.delta.usage != null) {
          latestUsage = event.delta.usage;
        }

        _updateTurn(
          assistantId,
          (t) => t.copyWith(
            text: buffer.toString(),
            providerLabel: activeLabel,
            modelLabel: activeModel,
            usage: latestUsage,
            isStreaming: true,
          ),
        );
      }

      if (latestUsage != null) {
        final total = _ref.read(sessionTokenUsageProvider);
        _ref.read(sessionTokenUsageProvider.notifier).state = total + latestUsage;
      }

      _updateTurn(
        assistantId,
        (t) => t.copyWith(
          text: buffer.isEmpty ? 'No response returned by provider.' : buffer.toString(),
          isError: buffer.isEmpty,
          isStreaming: false,
          usage: latestUsage,
        ),
      );
    } on AiException catch (error) {
      if (error.kind != AiErrorKind.cancelled) {
        _updateTurn(
          assistantId,
          (t) => t.copyWith(
            text: error.message,
            isError: true,
            isStreaming: false,
          ),
        );
      }
    } catch (error) {
      _updateTurn(
        assistantId,
        (t) => t.copyWith(
          text: 'Unexpected error: $error',
          isError: true,
          isStreaming: false,
        ),
      );
    } finally {
      _activeCancellation = null;
      state = false;
      _ref.read(orbStateProvider.notifier).state = DaneOrbState.idle;
    }
  }

  void _updateTurn(String id, ChatTurn Function(ChatTurn) transform) {
    final current = _ref.read(conversationTurnsProvider);
    _ref.read(conversationTurnsProvider.notifier).state = [
      for (final t in current)
        if (t.id == id) transform(t) else t,
    ];
  }
}

final chatControllerProvider = StateNotifierProvider<ChatController, bool>((ref) {
  return ChatController(ref);
});
