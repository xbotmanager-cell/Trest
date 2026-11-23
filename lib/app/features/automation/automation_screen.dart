import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hey_dane/app/core/theme/dane_colors.dart';
import 'package:hey_dane/app/features/automation/domain/dane_action.dart';
import 'package:hey_dane/app/shared/providers/app_state_provider.dart';
import 'package:hey_dane/app/shared/widgets/glass_surface.dart';

class AutomationScreen extends ConsumerStatefulWidget {
  const AutomationScreen({super.key});

  @override
  ConsumerState<AutomationScreen> createState() => _AutomationScreenState();
}

class _AutomationScreenState extends ConsumerState<AutomationScreen> {
  String? _selectedSafUri;
  String? _selectedSafName;
  List<Map<String, String>> _apps = const [];
  List<Map<String, dynamic>> _notifications = const [];
  String? _notificationNotice;
  bool _loadingApps = false;
  bool _loadingNotifications = false;

  Future<void> _submitAction(
    DaneAction action, {
    bool allowImmediate = true,
  }) async {
    final engine = ref.read(actionEngineProvider);
    final flags = ref.read(automationFeatureFlagsProvider);

    if (action.requiresConfirmation || !allowImmediate) {
      final pending = ref.read(pendingActionsProvider);
      ref.read(pendingActionsProvider.notifier).state = [action, ...pending];
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${action.type.label} added to Pending Confirmations.'),
        ),
      );
      return;
    }

    final executed = await engine.execute(action, featureFlags: flags);
    _recordHistory(executed);

    if (action.type == DaneActionType.pickFileSaf &&
        executed.status == ActionExecutionStatus.succeeded) {
      final uri = executed.resultData?['uri']?.toString();
      final name = executed.resultData?['name']?.toString();
      if (uri != null && uri.isNotEmpty && mounted) {
        setState(() {
          _selectedSafUri = uri;
          _selectedSafName = name ?? 'Selected Document';
        });
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(executed.resultMessage ?? executed.status.name),
      ),
    );
  }

  Future<void> _approvePending(DaneAction action) async {
    final engine = ref.read(actionEngineProvider);
    final flags = ref.read(automationFeatureFlagsProvider);
    _removePending(action.id);

    final executed = await engine.execute(
      action,
      featureFlags: flags,
      userConfirmed: true,
    );
    _recordHistory(executed);

    if (action.type == DaneActionType.deleteFileSaf &&
        executed.status == ActionExecutionStatus.succeeded &&
        mounted) {
      setState(() {
        _selectedSafUri = null;
        _selectedSafName = null;
      });
    } else if (action.type == DaneActionType.renameFileSaf &&
        executed.status == ActionExecutionStatus.succeeded &&
        mounted) {
      final updatedUri = executed.resultData?['uri']?.toString();
      final newName = action.parameters['newName']?.toString();
      setState(() {
        if (updatedUri != null && updatedUri.isNotEmpty) {
          _selectedSafUri = updatedUri;
        }
        if (newName != null && newName.isNotEmpty) {
          _selectedSafName = newName;
        }
      });
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(executed.resultMessage ?? 'Executed.')),
    );
  }

  void _rejectPending(DaneAction action) {
    _removePending(action.id);
    _recordHistory(
      action.copyWith(
        status: ActionExecutionStatus.rejected,
        resultMessage: 'Rejected by user before execution.',
      ),
    );
  }

  void _removePending(String id) {
    final pending = ref.read(pendingActionsProvider);
    ref.read(pendingActionsProvider.notifier).state =
        pending.where((a) => a.id != id).toList();
  }

  void _recordHistory(DaneAction action) {
    final history = ref.read(automationHistoryProvider);
    ref.read(automationHistoryProvider.notifier).state = [
      action,
      ...history.take(29),
    ];
  }

  Future<void> _loadApps() async {
    setState(() => _loadingApps = true);
    final apps = await ref.read(actionEngineProvider).listLaunchableApps();
    if (!mounted) return;
    setState(() {
      _apps = apps;
      _loadingApps = false;
    });
    if (apps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No launchable Android apps returned on current host.',
          ),
        ),
      );
    }
  }

  Future<void> _loadNotifications() async {
    setState(() => _loadingNotifications = true);
    final res = await ref.read(actionEngineProvider).getRecentNotifications();
    if (!mounted) return;
    final rawItems = res['items'];
    final items = rawItems is List
        ? rawItems.whereType<Map<dynamic, dynamic>>().map((m) {
            return m.map((k, v) => MapEntry(k.toString(), v));
          }).toList()
        : const <Map<String, dynamic>>[];
    setState(() {
      _notifications = items;
      _notificationNotice = res['message']?.toString();
      _loadingNotifications = false;
    });
  }

  Future<void> _promptAlarm() async {
    final now = TimeOfDay.now();
    final picked = await showTimePicker(context: context, initialTime: now);
    if (picked == null || !mounted) return;
    final action = ref.read(alarmServiceProvider).proposeAlarm(
          hour: picked.hour,
          minute: picked.minute,
        );
    await _submitAction(action);
  }

  Future<void> _promptTimer() async {
    final controller = TextEditingController(text: '300');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Propose Countdown Timer'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Duration (seconds)',
            hintText: 'e.g. 300',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Queue Action'),
          ),
        ],
      ),
    );
    final seconds = int.tryParse(controller.text.trim());
    controller.dispose();
    if (confirmed != true || seconds == null) return;
    final action =
        ref.read(alarmServiceProvider).proposeTimer(seconds: seconds);
    await _submitAction(action);
  }

  Future<void> _promptPhoneAction({required bool directCall}) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(directCall ? 'Direct Call (High Risk)' : 'Open Dialer'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Phone number',
            hintText: '+254700000000',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Queue Confirmation'),
          ),
        ],
      ),
    );
    final number = controller.text.trim();
    controller.dispose();
    if (confirmed != true || number.isEmpty) return;
    final calls = ref.read(callServiceProvider);
    await _submitAction(
      directCall
          ? calls.proposePlaceCall(number)
          : calls.proposeOpenDialer(number),
    );
  }

  Future<void> _promptMessageAction({required String mode}) async {
    final phoneController = TextEditingController();
    final bodyController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          switch (mode) {
            'sms_direct' => 'Send Direct SMS (High Risk)',
            'whatsapp' => 'WhatsApp Handoff',
            _ => 'Compose SMS',
          },
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Recipient number'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: bodyController,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Message text'),
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
            child: const Text('Queue Confirmation'),
          ),
        ],
      ),
    );
    final phone = phoneController.text.trim();
    final body = bodyController.text.trim();
    phoneController.dispose();
    bodyController.dispose();
    if (confirmed != true || phone.isEmpty) return;

    final msgs = ref.read(messagingServiceProvider);
    final action = switch (mode) {
      'sms_direct' => msgs.proposeSendSms(phoneNumber: phone, body: body),
      'whatsapp' => msgs.proposeWhatsAppHandoff(phoneNumber: phone, text: body),
      _ => msgs.proposeComposeSms(phoneNumber: phone, body: body),
    };
    await _submitAction(action);
  }

  Future<void> _promptRenameSaf() async {
    final uri = _selectedSafUri;
    if (uri == null) return;
    final controller = TextEditingController(text: _selectedSafName ?? '');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename SAF Document'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'New filename'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Queue Confirmation'),
          ),
        ],
      ),
    );
    final newName = controller.text.trim();
    controller.dispose();
    if (confirmed != true || newName.isEmpty) return;
    await _submitAction(
      ref.read(fileServiceProvider).proposeRenameFileSaf(
            uri: uri,
            newName: newName,
          ),
    );
  }

  Future<void> _promptDownloadHttps() async {
    final urlController = TextEditingController(text: 'https://');
    final nameController = TextEditingController(text: 'document.pdf');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enqueue HTTPS Download'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: urlController,
              decoration: const InputDecoration(labelText: 'HTTPS URL'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Target filename'),
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
            child: const Text('Queue Confirmation'),
          ),
        ],
      ),
    );
    final url = urlController.text.trim();
    final fileName = nameController.text.trim();
    urlController.dispose();
    nameController.dispose();
    if (confirmed != true || url.isEmpty || fileName.isEmpty) return;
    await _submitAction(
      ref.read(fileServiceProvider).proposeHttpsDownload(
            url: url,
            fileName: fileName,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(pendingActionsProvider);
    final history = ref.watch(automationHistoryProvider);
    final engine = ref.read(actionEngineProvider);
    final alarms = ref.read(alarmServiceProvider);
    final files = ref.read(fileServiceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Device Automation')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const GlassSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Structured Action Pipeline',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Every device action passes schema validation, feature toggles, permission checks, and explicit confirmation for medium/high-risk operations.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (pending.isNotEmpty) ...[
              Text(
                'Pending Confirmations (${pending.length})',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: DaneColors.cautionAmber,
                    ),
              ),
              const SizedBox(height: 8),
              for (final action in pending)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GlassSurface(
                    padding: const EdgeInsets.all(14),
                    borderRadius: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              action.type.label,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            _RiskBadge(level: action.riskLevel),
                          ],
                        ),
                        if (action.parameters.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            action.parameters.entries
                                .map((e) => '${e.key}: ${e.value}')
                                .join(' · '),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => _rejectPending(action),
                              child: const Text('Reject'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: () => _approvePending(action),
                              child: const Text('Approve & Execute'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
            ],
            GlassSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Apps & System Panels',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _loadingApps ? null : _loadApps,
                        icon: const Icon(Icons.apps_rounded, size: 18),
                        label: Text(
                          _loadingApps
                              ? 'Loading Apps...'
                              : 'List Installed Apps',
                        ),
                      ),
                      for (final panel in const [
                        'wifi',
                        'bluetooth',
                        'display',
                        'sound',
                        'location',
                      ])
                        OutlinedButton(
                          onPressed: () => _submitAction(
                            engine.buildAction(
                              type: DaneActionType.openSystemSetting,
                              parameters: {'panel': panel},
                            ),
                          ),
                          child: Text(
                            '${panel[0].toUpperCase()}${panel.substring(1)} Settings',
                          ),
                        ),
                    ],
                  ),
                  if (_apps.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 160,
                      child: ListView.builder(
                        itemCount: _apps.length,
                        itemBuilder: (context, index) {
                          final app = _apps[index];
                          final pkg = app['packageName'] ?? '';
                          final label = app['label'] ?? pkg;
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(label),
                            subtitle: Text(pkg),
                            trailing:
                                const Icon(Icons.open_in_new_rounded, size: 18),
                            onTap: () => _submitAction(
                              engine.buildAction(
                                type: DaneActionType.launchApp,
                                parameters: {'packageName': pkg},
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            GlassSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Accessibility, Notifications & Device Admin',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final act in const [
                        'back',
                        'home',
                        'recents',
                        'notifications'
                      ])
                        OutlinedButton(
                          onPressed: () => _submitAction(
                            engine.buildAction(
                              type: DaneActionType.accessibilityAction,
                              parameters: {'actionName': act},
                            ),
                          ),
                          child: Text('Nav: $act'),
                        ),
                      OutlinedButton.icon(
                        onPressed: () => _submitAction(
                          engine.buildAction(
                            type: DaneActionType.lockDeviceAdmin,
                            parameters: const {},
                          ),
                        ),
                        icon: const Icon(Icons.lock_outline_rounded, size: 18),
                        label: const Text('Lock Screen'),
                      ),
                      FilledButton.tonal(
                        onPressed:
                            _loadingNotifications ? null : _loadNotifications,
                        child: Text(
                          _loadingNotifications
                              ? 'Reading...'
                              : 'Read Notification Buffer',
                        ),
                      ),
                      if (_notifications.isNotEmpty)
                        TextButton(
                          onPressed: () async {
                            await engine.clearNotifications();
                            if (mounted) {
                              setState(() {
                                _notifications = const [];
                                _notificationNotice = 'Cleared buffer.';
                              });
                            }
                          },
                          child: const Text('Clear Buffer'),
                        ),
                    ],
                  ),
                  if (_notificationNotice != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _notificationNotice!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  for (final n in _notifications.take(5))
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '${n['packageName']}: ${n['title']} — ${n['text']}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GlassSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Alarms, Calls & Messaging',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonal(
                        onPressed: _promptAlarm,
                        child: const Text('Propose Alarm'),
                      ),
                      FilledButton.tonal(
                        onPressed: _promptTimer,
                        child: const Text('Propose Timer'),
                      ),
                      OutlinedButton(
                        onPressed: () =>
                            _submitAction(alarms.proposeShowAlarms()),
                        child: const Text('Show Alarms'),
                      ),
                      OutlinedButton(
                        onPressed: () => _promptPhoneAction(directCall: false),
                        child: const Text('Open Dialer'),
                      ),
                      OutlinedButton(
                        onPressed: () => _promptPhoneAction(directCall: true),
                        child: const Text('Place Call'),
                      ),
                      OutlinedButton(
                        onPressed: () =>
                            _promptMessageAction(mode: 'sms_compose'),
                        child: const Text('Compose SMS'),
                      ),
                      OutlinedButton(
                        onPressed: () =>
                            _promptMessageAction(mode: 'sms_direct'),
                        child: const Text('Send SMS'),
                      ),
                      OutlinedButton(
                        onPressed: () => _promptMessageAction(mode: 'whatsapp'),
                        child: const Text('WhatsApp Handoff'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GlassSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Files (SAF), MediaStore & HTTPS Downloads',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonal(
                        onPressed: () =>
                            _submitAction(files.proposePickFileSaf()),
                        child: const Text('Pick Document (SAF)'),
                      ),
                      OutlinedButton(
                        onPressed: () =>
                            _submitAction(files.proposeBrowseMedia()),
                        child: const Text('Browse MediaStore'),
                      ),
                      OutlinedButton(
                        onPressed: _promptDownloadHttps,
                        child: const Text('HTTPS Download'),
                      ),
                      if (_selectedSafUri != null) ...[
                        OutlinedButton(
                          onPressed: _promptRenameSaf,
                          child: const Text('Rename Selected'),
                        ),
                        OutlinedButton(
                          onPressed: () => _submitAction(
                            files.proposeDeleteFileSaf(_selectedSafUri!),
                          ),
                          child: const Text('Delete Selected'),
                        ),
                      ],
                    ],
                  ),
                  if (_selectedSafName != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Selected SAF file: $_selectedSafName',
                      style: const TextStyle(
                        fontSize: 12,
                        color: DaneColors.cyanCore,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Verified Execution History (${history.length})',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            if (history.isEmpty)
              GlassSurface(
                padding: const EdgeInsets.all(14),
                child: Text(
                  'No automation actions executed in this session yet.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else
              for (final item in history)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: GlassSurface(
                    padding: const EdgeInsets.all(12),
                    borderRadius: 14,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          item.status == ActionExecutionStatus.succeeded
                              ? Icons.check_circle_outline_rounded
                              : item.status == ActionExecutionStatus.rejected
                                  ? Icons.block_rounded
                                  : Icons.error_outline_rounded,
                          size: 18,
                          color: item.status == ActionExecutionStatus.succeeded
                              ? DaneColors.nominalGreen
                              : item.status == ActionExecutionStatus.rejected
                                  ? DaneColors.cautionAmber
                                  : DaneColors.alertCrimson,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${item.type.label} · ${item.status.name}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (item.resultMessage != null)
                                Text(
                                  item.resultMessage!,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
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

class _RiskBadge extends StatelessWidget {
  const _RiskBadge({required this.level});

  final ActionRiskLevel level;

  @override
  Widget build(BuildContext context) {
    final color = switch (level) {
      ActionRiskLevel.low => DaneColors.nominalGreen,
      ActionRiskLevel.medium => DaneColors.cautionAmber,
      ActionRiskLevel.high => DaneColors.alertCrimson,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Text(
        '${level.name.toUpperCase()} RISK',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
