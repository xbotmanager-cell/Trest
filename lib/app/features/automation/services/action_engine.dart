import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hey_dane/app/core/constants/app_identity.dart';
import 'package:hey_dane/app/features/automation/domain/dane_action.dart';
import 'package:uuid/uuid.dart';

abstract class NativeAutomationGateway {
  Future<Map<String, dynamic>> invokeAction(
    String method,
    Map<String, dynamic> args,
  );
  Future<List<Map<String, String>>> listLaunchableApps();
}

class MethodChannelAutomationGateway implements NativeAutomationGateway {
  MethodChannelAutomationGateway({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(AppIdentity.automationChannel);

  final MethodChannel _channel;

  @override
  Future<Map<String, dynamic>> invokeAction(
    String method,
    Map<String, dynamic> args,
  ) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return {
        'success': false,
        'message': 'Native Android automation requires an Android device.',
      };
    }
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(method, args);
      return res ?? {'success': false, 'message': 'No native result returned.'};
    } on PlatformException catch (e) {
      return {'success': false, 'message': e.message ?? 'Native call failed.'};
    } on MissingPluginException {
      return {'success': false, 'message': 'Automation channel not registered.'};
    }
  }

  @override
  Future<List<Map<String, String>>> listLaunchableApps() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const [];
    }
    try {
      final list = await _channel.invokeListMethod<dynamic>('listLaunchableApps');
      if (list == null) return const [];
      return list
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (m) => {
              'label': (m['label'] ?? '').toString(),
              'packageName': (m['packageName'] ?? '').toString(),
            },
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }
}

class ActionEngine {
  ActionEngine({NativeAutomationGateway? gateway})
      : _gateway = gateway ?? MethodChannelAutomationGateway();

  final NativeAutomationGateway _gateway;
  final Uuid _uuid = const Uuid();

  static const Set<String> _blockedKeys = {
    'shell',
    'command',
    'exec',
    'su',
    'root',
    'password',
    'pin',
    'biometric',
  };

  /// Parses an AI-proposed structured JSON action safely.
  /// Rejects arbitrary shell commands, unrestricted file paths, or unknown types.
  DaneAction? parseProposalFromAi(String jsonPayload) {
    try {
      final decoded = jsonDecode(jsonPayload);
      if (decoded is! Map<String, dynamic>) return null;
      final typeName = decoded['type'] as String?;
      final params = decoded['parameters'];
      if (typeName == null || params is! Map<String, dynamic>) return null;

      for (final key in params.keys) {
        if (_blockedKeys.contains(key.toLowerCase())) {
          return null;
        }
      }

      final matchedType = DaneActionType.values.cast<DaneActionType?>().firstWhere(
            (t) => t?.name == typeName,
            orElse: () => null,
          );
      if (matchedType == null) return null;

      return buildAction(type: matchedType, parameters: params);
    } catch (_) {
      return null;
    }
  }

  DaneAction buildAction({
    required DaneActionType type,
    required Map<String, dynamic> parameters,
  }) {
    final (risk, perms, confirm) = switch (type) {
      DaneActionType.launchApp => (
          ActionRiskLevel.low,
          const <String>[],
          false,
        ),
      DaneActionType.openSystemSetting => (
          ActionRiskLevel.low,
          const <String>[],
          false,
        ),
      DaneActionType.showAlarms => (
          ActionRiskLevel.low,
          const <String>[],
          false,
        ),
      DaneActionType.browseMedia => (
          ActionRiskLevel.low,
          const ['READ_MEDIA_IMAGES', 'READ_MEDIA_VIDEO', 'READ_MEDIA_AUDIO'],
          false,
        ),
      DaneActionType.pickFileSaf => (
          ActionRiskLevel.low,
          const <String>[],
          false,
        ),
      DaneActionType.shareText => (
          ActionRiskLevel.low,
          const <String>[],
          false,
        ),
      DaneActionType.openDialer => (
          ActionRiskLevel.medium,
          const <String>[],
          true,
        ),
      DaneActionType.composeSms => (
          ActionRiskLevel.medium,
          const <String>[],
          true,
        ),
      DaneActionType.handoffWhatsApp => (
          ActionRiskLevel.medium,
          const <String>[],
          true,
        ),
      DaneActionType.setAlarm => (
          ActionRiskLevel.medium,
          const ['SET_ALARM'],
          true,
        ),
      DaneActionType.setTimer => (
          ActionRiskLevel.medium,
          const ['SET_ALARM'],
          true,
        ),
      DaneActionType.accessibilityAction => (
          ActionRiskLevel.medium,
          const ['BIND_ACCESSIBILITY_SERVICE'],
          true,
        ),
      DaneActionType.renameFileSaf => (
          ActionRiskLevel.medium,
          const <String>[],
          true,
        ),
      DaneActionType.downloadHttps => (
          ActionRiskLevel.medium,
          const ['INTERNET'],
          true,
        ),
      DaneActionType.placeCall => (
          ActionRiskLevel.high,
          const ['CALL_PHONE'],
          true,
        ),
      DaneActionType.sendSms => (
          ActionRiskLevel.high,
          const ['SEND_SMS'],
          true,
        ),
      DaneActionType.deleteFileSaf => (
          ActionRiskLevel.high,
          const <String>[],
          true,
        ),
      DaneActionType.lockDeviceAdmin => (
          ActionRiskLevel.high,
          const ['BIND_DEVICE_ADMIN'],
          true,
        ),
    };

    return DaneAction(
      id: _uuid.v4(),
      type: type,
      parameters: Map<String, dynamic>.unmodifiable(parameters),
      requiredPermissions: perms,
      riskLevel: risk,
      requiresConfirmation: confirm,
      status: confirm
          ? ActionExecutionStatus.awaitingConfirmation
          : ActionExecutionStatus.proposed,
      createdAt: DateTime.now(),
    );
  }

  String? validateParameters(DaneAction action) {
    final p = action.parameters;
    switch (action.type) {
      case DaneActionType.launchApp:
        final pkg = (p['packageName'] ?? '').toString().trim();
        if (pkg.isEmpty || pkg.contains(' ')) return 'Invalid packageName.';
      case DaneActionType.setAlarm:
        final hour = p['hour'];
        final minute = p['minute'];
        if (hour is! int || minute is! int || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
          return 'Alarm hour must be 0..23 and minute 0..59.';
        }
      case DaneActionType.setTimer:
        final seconds = p['seconds'];
        if (seconds is! int || seconds <= 0) {
          return 'Timer seconds must be > 0.';
        }
      case DaneActionType.openDialer:
      case DaneActionType.placeCall:
        if ((p['phoneNumber'] ?? '').toString().trim().isEmpty) {
          return 'Phone number is required.';
        }
      case DaneActionType.sendSms:
        if ((p['phoneNumber'] ?? '').toString().trim().isEmpty ||
            (p['body'] ?? '').toString().trim().isEmpty) {
          return 'Recipient and message body are required.';
        }
      case DaneActionType.renameFileSaf:
        final name = (p['newName'] ?? '').toString().trim();
        if (name.isEmpty || name.contains('/') || name.contains('..')) {
          return 'Invalid filename.';
        }
      case DaneActionType.downloadHttps:
        final url = (p['url'] ?? '').toString().trim();
        if (!url.startsWith('https://')) {
          return 'Only HTTPS URLs are allowed.';
        }
      default:
        break;
    }
    return null;
  }

  bool isFeatureEnabled(DaneActionType type, AutomationFeatureFlags flags) {
    return switch (type) {
      DaneActionType.launchApp ||
      DaneActionType.openSystemSetting ||
      DaneActionType.accessibilityAction ||
      DaneActionType.lockDeviceAdmin =>
        flags.appsAndSettingsEnabled,
      DaneActionType.openDialer ||
      DaneActionType.placeCall ||
      DaneActionType.composeSms ||
      DaneActionType.sendSms ||
      DaneActionType.shareText ||
      DaneActionType.handoffWhatsApp =>
        flags.commsEnabled,
      DaneActionType.setAlarm ||
      DaneActionType.setTimer ||
      DaneActionType.showAlarms ||
      DaneActionType.pickFileSaf ||
      DaneActionType.renameFileSaf ||
      DaneActionType.deleteFileSaf ||
      DaneActionType.browseMedia ||
      DaneActionType.downloadHttps =>
        flags.alarmsAndFilesEnabled,
    };
  }

  Future<DaneAction> execute(
    DaneAction action, {
    required AutomationFeatureFlags featureFlags,
    bool userConfirmed = false,
  }) async {
    if (!isFeatureEnabled(action.type, featureFlags)) {
      return action.copyWith(
        status: ActionExecutionStatus.rejected,
        resultMessage: '${action.type.label} is disabled in Permission Center.',
      );
    }

    final validationError = validateParameters(action);
    if (validationError != null) {
      return action.copyWith(
        status: ActionExecutionStatus.failed,
        resultMessage: validationError,
      );
    }

    if (action.requiresConfirmation && !userConfirmed) {
      return action.copyWith(
        status: ActionExecutionStatus.awaitingConfirmation,
        resultMessage: 'Explicit user confirmation required before executing.',
      );
    }

    final (method, args) = switch (action.type) {
      DaneActionType.launchApp => ('launchApp', action.parameters),
      DaneActionType.openSystemSetting => ('openSettingPanel', action.parameters),
      DaneActionType.accessibilityAction => ('performAccessibilityAction', action.parameters),
      DaneActionType.setAlarm => ('setAlarm', action.parameters),
      DaneActionType.setTimer => ('setTimer', action.parameters),
      DaneActionType.showAlarms => ('showAlarms', const <String, dynamic>{}),
      DaneActionType.openDialer => ('openDialer', action.parameters),
      DaneActionType.placeCall => ('placeCall', action.parameters),
      DaneActionType.composeSms => ('composeSms', action.parameters),
      DaneActionType.sendSms => ('sendSms', action.parameters),
      DaneActionType.shareText => ('shareText', action.parameters),
      DaneActionType.handoffWhatsApp => ('handoffWhatsApp', action.parameters),
      DaneActionType.pickFileSaf => ('pickDocumentSaf', const <String, dynamic>{}),
      DaneActionType.renameFileSaf => ('renameDocumentSaf', action.parameters),
      DaneActionType.deleteFileSaf => ('deleteDocumentSaf', action.parameters),
      DaneActionType.browseMedia => ('queryRecentMedia', const <String, dynamic>{}),
      DaneActionType.downloadHttps => ('enqueueDownload', action.parameters),
      DaneActionType.lockDeviceAdmin => ('lockDeviceAdmin', const <String, dynamic>{}),
    };

    final nativeResult = await _gateway.invokeAction(method, args);
    final success = nativeResult['success'] == true;
    final message = (nativeResult['message'] ?? '').toString();

    return action.copyWith(
      status: success ? ActionExecutionStatus.succeeded : ActionExecutionStatus.failed,
      resultMessage: message.isEmpty ? (success ? 'Completed.' : 'Failed.') : message,
      resultData: nativeResult,
    );
  }

  Future<List<Map<String, String>>> listLaunchableApps() {
    return _gateway.listLaunchableApps();
  }

  Future<Map<String, dynamic>> getRecentNotifications() {
    return _gateway.invokeAction('getRecentNotifications', const {});
  }

  Future<Map<String, dynamic>> clearNotifications() {
    return _gateway.invokeAction('clearNotifications', const {});
  }
}
