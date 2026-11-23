import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hey_dane/app/core/constants/app_identity.dart';

class AndroidDeviceSnapshot {
  const AndroidDeviceSnapshot({
    required this.manufacturer,
    required this.model,
    required this.androidRelease,
    required this.sdkInt,
    required this.packageName,
    required this.isNativeConnected,
    this.lastBootMs = 0,
  });

  final String manufacturer;
  final String model;
  final String androidRelease;
  final int sdkInt;
  final String packageName;
  final bool isNativeConnected;
  final int lastBootMs;

  factory AndroidDeviceSnapshot.unavailable() {
    return const AndroidDeviceSnapshot(
      manufacturer: 'Unknown',
      model: 'Device',
      androidRelease: 'Android',
      sdkInt: 0,
      packageName: AppIdentity.packageId,
      isNativeConnected: false,
      lastBootMs: 0,
    );
  }
}

class NativePlatformService {
  NativePlatformService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(AppIdentity.platformChannel);

  final MethodChannel _channel;

  Future<AndroidDeviceSnapshot> getDeviceSnapshot() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return AndroidDeviceSnapshot.unavailable();
    }

    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('getDeviceInfo');
      if (result == null) {
        return AndroidDeviceSnapshot.unavailable();
      }
      final rawBoot = result['lastBootMs'];
      final bootMs = rawBoot is int ? rawBoot : 0;
      return AndroidDeviceSnapshot(
        manufacturer: (result['manufacturer'] as String?) ?? 'Android',
        model: (result['model'] as String?) ?? 'Device',
        androidRelease: (result['release'] as String?) ?? 'Unknown',
        sdkInt: (result['sdkInt'] as int?) ?? 0,
        packageName: (result['packageName'] as String?) ?? AppIdentity.packageId,
        isNativeConnected: true,
        lastBootMs: bootMs,
      );
    } on MissingPluginException {
      return AndroidDeviceSnapshot.unavailable();
    } on PlatformException {
      return AndroidDeviceSnapshot.unavailable();
    }
  }

  Future<bool> openAndroidSettings(String action) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      final opened = await _channel.invokeMethod<bool>(
        'openSettings',
        <String, dynamic>{'action': action},
      );
      return opened ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> startVoiceForegroundService() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      final started = await _channel.invokeMethod<bool>('startVoiceForegroundService');
      return started ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> stopVoiceForegroundService() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      final stopped = await _channel.invokeMethod<bool>('stopVoiceForegroundService');
      return stopped ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
