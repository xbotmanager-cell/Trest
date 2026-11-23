import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hey_dane/app/core/theme/dane_colors.dart';
import 'package:hey_dane/app/features/permissions/services/permission_center_service.dart';
import 'package:hey_dane/app/shared/providers/app_state_provider.dart';
import 'package:hey_dane/app/shared/widgets/glass_surface.dart';
import 'package:permission_handler/permission_handler.dart';

class PermissionDescriptor {
  const PermissionDescriptor({
    required this.category,
    required this.title,
    required this.purpose,
    required this.featureDependency,
    required this.permission,
  });

  final String category;
  final String title;
  final String purpose;
  final String featureDependency;
  final Permission permission;
}

class SpecialAccessDescriptor {
  const SpecialAccessDescriptor({
    required this.targetKey,
    required this.title,
    required this.purpose,
    required this.featureDependency,
  });

  final String targetKey;
  final String title;
  final String purpose;
  final String featureDependency;
}

class PermissionsScreen extends ConsumerStatefulWidget {
  const PermissionsScreen({super.key});

  @override
  ConsumerState<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends ConsumerState<PermissionsScreen>
    with WidgetsBindingObserver {
  static final List<PermissionDescriptor> runtimeDescriptors = [
    const PermissionDescriptor(
      category: 'Voice & Alerts',
      title: 'Microphone (RECORD_AUDIO)',
      purpose: 'Captures live speech and explicit Hey Dane voice commands.',
      featureDependency: 'Live Voice, Wake Phrase & Voice Foreground Service',
      permission: Permission.microphone,
    ),
    const PermissionDescriptor(
      category: 'Voice & Alerts',
      title: 'Notifications (POST_NOTIFICATIONS)',
      purpose: 'Shows active foreground voice controls on Android 13+.',
      featureDependency: 'Foreground Voice Indicator (Android 13+)',
      permission: Permission.notification,
    ),
    const PermissionDescriptor(
      category: 'Communications',
      title: 'Direct Call (CALL_PHONE)',
      purpose: 'Places explicitly confirmed direct calls via Android Telecom.',
      featureDependency: 'Direct Call Automation (Dialer works without it)',
      permission: Permission.phone,
    ),
    const PermissionDescriptor(
      category: 'Communications',
      title: 'Direct SMS (SEND_SMS)',
      purpose: 'Dispatches explicitly confirmed SMS messages via SmsManager.',
      featureDependency: 'Direct SMS Automation (Composer works without it)',
      permission: Permission.sms,
    ),
    const PermissionDescriptor(
      category: 'Media & Storage',
      title: 'Photos (READ_MEDIA_IMAGES)',
      purpose: 'Reads recent images via MediaStore on Android 13+.',
      featureDependency: 'MediaStore File Browsing (Android 13+)',
      permission: Permission.photos,
    ),
    const PermissionDescriptor(
      category: 'Media & Storage',
      title: 'Videos (READ_MEDIA_VIDEO)',
      purpose: 'Reads recent videos via MediaStore on Android 13+.',
      featureDependency: 'MediaStore File Browsing (Android 13+)',
      permission: Permission.videos,
    ),
    const PermissionDescriptor(
      category: 'Media & Storage',
      title: 'Audio (READ_MEDIA_AUDIO)',
      purpose: 'Reads recent audio files via MediaStore on Android 13+.',
      featureDependency: 'MediaStore File Browsing (Android 13+)',
      permission: Permission.audio,
    ),
    const PermissionDescriptor(
      category: 'Media & Storage',
      title: 'Legacy Storage (READ_EXTERNAL_STORAGE)',
      purpose: 'Reads shared media on Android 12 (API 32) and below.',
      featureDependency: 'MediaStore File Browsing (Android 8–12)',
      permission: Permission.storage,
    ),
  ];

  static const List<SpecialAccessDescriptor> specialDescriptors = [
    SpecialAccessDescriptor(
      targetKey: 'accessibility',
      title: 'Accessibility Service',
      purpose:
          'Performs user-confirmed Back/Home/Recents actions. Never reads window content or passwords.',
      featureDependency: 'Navigation Global Actions',
    ),
    SpecialAccessDescriptor(
      targetKey: 'notifications',
      title: 'Notification Access',
      purpose: 'Reads posted notifications only while explicitly enabled.',
      featureDependency: 'Recent Notification Buffer Reader',
    ),
    SpecialAccessDescriptor(
      targetKey: 'overlay',
      title: 'Display Over Apps (SYSTEM_ALERT_WINDOW)',
      purpose: 'Displays floating confirmation sheets above other apps.',
      featureDependency: 'Overlay Confirmation Prompts',
    ),
    SpecialAccessDescriptor(
      targetKey: 'exactAlarm',
      title: 'Exact Alarms (SCHEDULE_EXACT_ALARM)',
      purpose: 'Schedules exact alarms and timers reliably on Android 12+.',
      featureDependency: 'Exact Alarm & Reminder Scheduling',
    ),
    SpecialAccessDescriptor(
      targetKey: 'battery',
      title: 'Ignore Battery Optimizations',
      purpose:
          'Reduces OS termination during active voice sessions. May raise battery use while active.',
      featureDependency: 'Uninterrupted Voice Foreground Sessions',
    ),
    SpecialAccessDescriptor(
      targetKey: 'deviceAdmin',
      title: 'Device Administrator (Screen Lock Only)',
      purpose:
          'Strictly enforces force-lock on explicit user command. No broader policy access.',
      featureDependency: 'Lock Screen Automation Action',
    ),
  ];

  final Map<Permission, DanePermissionState> _statuses = {};
  SpecialAccessSnapshot _specialSnapshot = const SpecialAccessSnapshot();
  bool _loading = true;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshAll();
    }
  }

  Future<void> _refreshAll() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _lastError = null;
      });
    }
    final service = ref.read(permissionCenterServiceProvider);
    final special = await service.getSpecialAccessSnapshot();
    final runtime = await service.checkRuntimePermissions(
      runtimeDescriptors.map((d) => d.permission).toList(),
      sdkInt: special.sdkInt,
    );

    if (!mounted) return;
    setState(() {
      _statuses
        ..clear()
        ..addAll(runtime);
      _specialSnapshot = special;
      _loading = false;
    });
  }

  Future<void> _requestRuntime(Permission permission) async {
    final service = ref.read(permissionCenterServiceProvider);
    final res = await service.requestRuntimePermission(
      permission,
      sdkInt: _specialSnapshot.sdkInt,
    );
    if (!mounted) return;
    if (res.error != null) {
      setState(() => _lastError = res.error);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.error!)),
      );
    }
    await _refreshAll();
  }

  Future<void> _openSpecial(String targetKey) async {
    final service = ref.read(permissionCenterServiceProvider);
    final res = await service.openSpecialAccessSettings(targetKey);
    if (!mounted) return;
    if (!res.opened && res.error != null) {
      setState(() => _lastError = res.error);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.error!)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final featureFlags = ref.watch(automationFeatureFlagsProvider);

    final applicableRuntime = runtimeDescriptors.where((d) {
      final st = _statuses[d.permission] ?? DanePermissionState.denied;
      return st != DanePermissionState.notRequired;
    }).toList();

    final grantedRuntime = applicableRuntime
        .where((d) => _statuses[d.permission] == DanePermissionState.granted)
        .length;

    final applicableSpecial = specialDescriptors.where((s) {
      final st = PermissionCenterService.resolveSpecialState(
        targetKey: s.targetKey,
        snapshot: _specialSnapshot,
      );
      return st != DanePermissionState.notRequired;
    }).toList();

    final enabledTotal = grantedRuntime + _specialSnapshot.enabledSpecialCount;
    final totalChecks = applicableRuntime.length + applicableSpecial.length;
    final progress = totalChecks == 0 ? 0.0 : enabledTotal / totalChecks;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Permission Center'),
        actions: [
          IconButton(
            tooltip: 'Refresh permission status',
            onPressed: _refreshAll,
            icon: const Icon(Icons.refresh_rounded),
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
                        'Setup Progress',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '$enabledTotal / $totalChecks granted',
                        style: const TextStyle(
                          fontSize: 13,
                          color: DaneColors.cyanCore,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: _loading ? null : progress,
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _loading
                        ? 'Verifying live Android runtime and special-access permissions...'
                        : 'Statuses refresh automatically when returning from Android Settings. '
                            'Grant only permissions for modules you choose to enable.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (_lastError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _lastError!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: DaneColors.alertCrimson,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Runtime Permissions',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            for (final item in runtimeDescriptors)
              _PermissionItemCard(
                category: item.category,
                title: item.title,
                purpose: item.purpose,
                featureDependency: item.featureDependency,
                status: _statuses[item.permission] ?? DanePermissionState.denied,
                onAction: () => _requestRuntime(item.permission),
                onManageSettings: () => openAppSettings(),
              ),
            const SizedBox(height: 14),
            Text(
              'Special Android Access',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            for (final spec in specialDescriptors)
              _PermissionItemCard(
                category: 'Android Special Access',
                title: spec.title,
                purpose: spec.purpose,
                featureDependency: spec.featureDependency,
                status: PermissionCenterService.resolveSpecialState(
                  targetKey: spec.targetKey,
                  snapshot: _specialSnapshot,
                ),
                onAction: () => _openSpecial(spec.targetKey),
                onManageSettings: () => _openSpecial(spec.targetKey),
              ),
            const SizedBox(height: 14),
            GlassSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Feature Controls (Disable Anytime)',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('App Launching & Settings'),
                    value: featureFlags.appsAndSettingsEnabled,
                    onChanged: (v) {
                      ref.read(automationFeatureFlagsProvider.notifier).state =
                          featureFlags.copyWith(appsAndSettingsEnabled: v);
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Calls & Messaging Handoff'),
                    value: featureFlags.commsEnabled,
                    onChanged: (v) {
                      ref.read(automationFeatureFlagsProvider.notifier).state =
                          featureFlags.copyWith(commsEnabled: v);
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Alarms & File SAF Operations'),
                    value: featureFlags.alarmsAndFilesEnabled,
                    onChanged: (v) {
                      ref.read(automationFeatureFlagsProvider.notifier).state =
                          featureFlags.copyWith(alarmsAndFilesEnabled: v);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            GlassSurface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Permission Troubleshooting',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '• Android 13+ Restricted Settings: If Accessibility or Notification Access is grayed out for sideloaded APKs, open App Info > More (⋮) > Allow restricted settings.\n'
                    '• Foreground Microphone Service: Android 14+ requires RECORD_AUDIO to be granted before starting the visible microphone foreground notification.',
                    style: Theme.of(context).textTheme.bodySmall,
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

class _PermissionItemCard extends StatelessWidget {
  const _PermissionItemCard({
    required this.category,
    required this.title,
    required this.purpose,
    required this.featureDependency,
    required this.status,
    required this.onAction,
    required this.onManageSettings,
  });

  final String category;
  final String title;
  final String purpose;
  final String featureDependency;
  final DanePermissionState status;
  final VoidCallback onAction;
  final VoidCallback onManageSettings;

  @override
  Widget build(BuildContext context) {
    final badgeColor = switch (status) {
      DanePermissionState.granted => DaneColors.nominalGreen,
      DanePermissionState.denied => DaneColors.cautionAmber,
      DanePermissionState.permanentlyDenied ||
      DanePermissionState.restricted =>
        DaneColors.alertCrimson,
      DanePermissionState.notRequired => DaneColors.textSecondaryDark,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassSurface(
        padding: const EdgeInsets.all(14),
        borderRadius: 16,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    category,
                    style: const TextStyle(
                      fontSize: 11,
                      color: DaneColors.cyanCore,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: badgeColor),
                  ),
                  child: Text(
                    status.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: badgeColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(purpose, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              'Feature dependency: $featureDependency',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: DaneColors.textSecondaryDark,
                  ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: switch (status) {
                DanePermissionState.notRequired => const OutlinedButton(
                    onPressed: null,
                    child: Text('Not Required on OS'),
                  ),
                DanePermissionState.granted => OutlinedButton(
                    onPressed: onManageSettings,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: DaneColors.nominalGreen,
                      side: const BorderSide(color: DaneColors.nominalGreen),
                    ),
                    child: const Text('Open Settings'),
                  ),
                DanePermissionState.permanentlyDenied ||
                DanePermissionState.restricted =>
                  FilledButton.tonal(
                    onPressed: onManageSettings,
                    child: const Text('Open Settings'),
                  ),
                DanePermissionState.denied => FilledButton.tonal(
                    onPressed: onAction,
                    child: const Text('Enable / Configure'),
                  ),
              },
            ),
          ],
        ),
      ),
    );
  }
}
