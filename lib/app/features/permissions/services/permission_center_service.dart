import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hey_dane/app/core/constants/app_identity.dart';
import 'package:permission_handler/permission_handler.dart';

enum DanePermissionState {
  granted('Granted'),
  denied('Denied'),
  permanentlyDenied('Permanently Denied'),
  restricted('Restricted'),
  notRequired('Not Required');

  const DanePermissionState(this.label);
  final String label;
}

class SpecialAccessSnapshot {
  const SpecialAccessSnapshot({
    this.sdkInt = 0,
    this.accessibilityEnabled = false,
    this.notificationAccessEnabled = false,
    this.deviceAdminEnabled = false,
    this.overlayEnabled = false,
    this.exactAlarmEnabled = false,
    this.batteryOptimizationIgnored = false,
    this.foregroundServiceRunning = false,
  });

  final int sdkInt;
  final bool accessibilityEnabled;
  final bool notificationAccessEnabled;
  final bool deviceAdminEnabled;
  final bool overlayEnabled;
  final bool exactAlarmEnabled;
  final bool batteryOptimizationIgnored;
  final bool foregroundServiceRunning;

  int get enabledSpecialCount => [
        accessibilityEnabled,
        notificationAccessEnabled,
        deviceAdminEnabled,
        overlayEnabled,
        if (sdkInt == 0 || sdkInt >= 31) exactAlarmEnabled,
        batteryOptimizationIgnored,
      ].where((v) => v).length;
}

class PermissionCenterService {
  PermissionCenterService({MethodChannel? channel})
      : _channel =
            channel ?? const MethodChannel(AppIdentity.permissionsChannel);

  final MethodChannel _channel;

  static DanePermissionState mapRuntimeStatus({
    required Permission permission,
    required PermissionStatus status,
    required int sdkInt,
  }) {
    if (sdkInt > 0 && sdkInt < 33) {
      if (permission == Permission.notification ||
          permission == Permission.photos ||
          permission == Permission.videos ||
          permission == Permission.audio) {
        return DanePermissionState.notRequired;
      }
    }
    if (sdkInt >= 33 && permission == Permission.storage) {
      return DanePermissionState.notRequired;
    }

    if (status.isGranted || status.isLimited || status.isProvisional) {
      return DanePermissionState.granted;
    }
    if (status.isPermanentlyDenied) {
      return DanePermissionState.permanentlyDenied;
    }
    if (status.isRestricted) {
      return DanePermissionState.restricted;
    }
    return DanePermissionState.denied;
  }

  static DanePermissionState resolveSpecialState({
    required String targetKey,
    required SpecialAccessSnapshot snapshot,
  }) {
    if (targetKey == 'exactAlarm' &&
        snapshot.sdkInt > 0 &&
        snapshot.sdkInt < 31) {
      return DanePermissionState.notRequired;
    }

    final enabled = switch (targetKey) {
      'accessibility' => snapshot.accessibilityEnabled,
      'notifications' => snapshot.notificationAccessEnabled,
      'overlay' => snapshot.overlayEnabled,
      'exactAlarm' => snapshot.exactAlarmEnabled,
      'battery' => snapshot.batteryOptimizationIgnored,
      'deviceAdmin' => snapshot.deviceAdminEnabled,
      _ => false,
    };

    return enabled ? DanePermissionState.granted : DanePermissionState.denied;
  }

  Future<SpecialAccessSnapshot> getSpecialAccessSnapshot() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const SpecialAccessSnapshot();
    }
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'getSpecialAccessSnapshot',
      );
      if (raw == null) return const SpecialAccessSnapshot();
      final rawSdk = raw['sdkInt'];
      return SpecialAccessSnapshot(
        sdkInt: rawSdk is int ? rawSdk : 0,
        accessibilityEnabled: raw['accessibilityEnabled'] == true,
        notificationAccessEnabled: raw['notificationAccessEnabled'] == true,
        deviceAdminEnabled: raw['deviceAdminEnabled'] == true,
        overlayEnabled: raw['overlayEnabled'] == true,
        exactAlarmEnabled: raw['exactAlarmEnabled'] == true,
        batteryOptimizationIgnored: raw['batteryOptimizationIgnored'] == true,
        foregroundServiceRunning: raw['foregroundServiceRunning'] == true,
      );
    } on MissingPluginException {
      return const SpecialAccessSnapshot();
    } on PlatformException {
      return const SpecialAccessSnapshot();
    }
  }

  Future<({bool opened, String? error})> openSpecialAccessSettings(
    String target,
  ) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return (
        opened: false,
        error: 'Android Settings can only be opened on an Android device.',
      );
    }
    try {
      final opened = await _channel.invokeMethod<bool>(
        'openSpecialAccessSettings',
        {'target': target},
      );
      if (opened == true) {
        return (opened: true, error: null);
      }
      return (
        opened: false,
        error: 'Unable to open Android settings for "$target".',
      );
    } on PlatformException catch (e) {
      return (
        opened: false,
        error: e.message ?? 'Settings intent failed for "$target".',
      );
    } on MissingPluginException {
      return (
        opened: false,
        error: 'Native permissions channel is not registered.',
      );
    }
  }

  Future<Map<Permission, DanePermissionState>> checkRuntimePermissions(
    List<Permission> permissions, {
    required int sdkInt,
  }) async {
    final map = <Permission, DanePermissionState>{};
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      for (final p in permissions) {
        map[p] = DanePermissionState.denied;
      }
      return map;
    }
    for (final p in permissions) {
      try {
        final raw = await p.status;
        map[p] = mapRuntimeStatus(
          permission: p,
          status: raw,
          sdkInt: sdkInt,
        );
      } catch (_) {
        map[p] = DanePermissionState.denied;
      }
    }
    return map;
  }

  Future<({DanePermissionState state, String? error})> requestRuntimePermission(
    Permission permission, {
    required int sdkInt,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return (
        state: DanePermissionState.denied,
        error: 'Runtime permissions require an Android device.',
      );
    }

    final current = await permission.status;
    final mappedCurrent = mapRuntimeStatus(
      permission: permission,
      status: current,
      sdkInt: sdkInt,
    );
    if (mappedCurrent == DanePermissionState.notRequired) {
      return (state: DanePermissionState.notRequired, error: null);
    }

    try {
      final requested = await permission.request();
      final mapped = mapRuntimeStatus(
        permission: permission,
        status: requested,
        sdkInt: sdkInt,
      );
      if (mapped == DanePermissionState.permanentlyDenied) {
        await openAppSettings();
      }
      return (state: mapped, error: null);
    } catch (e) {
      return (
        state: DanePermissionState.denied,
        error: 'Permission request failed: $e',
      );
    }
  }
}
