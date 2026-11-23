enum DaneActionType {
  launchApp('Launch App'),
  openSystemSetting('Open System Settings'),
  accessibilityAction('Accessibility Navigation'),
  setAlarm('Set Alarm'),
  setTimer('Set Timer'),
  showAlarms('Review Alarms'),
  openDialer('Open Dialer'),
  placeCall('Place Direct Call'),
  composeSms('Compose SMS'),
  sendSms('Send Direct SMS'),
  shareText('Share via Sharesheet'),
  handoffWhatsApp('WhatsApp Handoff'),
  pickFileSaf('Select File (SAF)'),
  renameFileSaf('Rename Selected File'),
  deleteFileSaf('Delete Selected File'),
  browseMedia('Browse Permitted Media'),
  downloadHttps('Download HTTPS File'),
  lockDeviceAdmin('Lock Screen (Device Admin)');

  const DaneActionType(this.label);
  final String label;
}

enum ActionRiskLevel { low, medium, high }

enum ActionExecutionStatus {
  proposed,
  awaitingConfirmation,
  executing,
  succeeded,
  failed,
  rejected,
}

class DaneAction {
  const DaneAction({
    required this.id,
    required this.type,
    required this.parameters,
    required this.requiredPermissions,
    required this.riskLevel,
    required this.requiresConfirmation,
    this.status = ActionExecutionStatus.proposed,
    this.resultMessage,
    this.resultData,
    this.createdAt,
  });

  final String id;
  final DaneActionType type;
  final Map<String, dynamic> parameters;
  final List<String> requiredPermissions;
  final ActionRiskLevel riskLevel;
  final bool requiresConfirmation;
  final ActionExecutionStatus status;
  final String? resultMessage;
  final Map<String, dynamic>? resultData;
  final DateTime? createdAt;

  DaneAction copyWith({
    ActionExecutionStatus? status,
    String? resultMessage,
    Map<String, dynamic>? resultData,
  }) {
    return DaneAction(
      id: id,
      type: type,
      parameters: parameters,
      requiredPermissions: requiredPermissions,
      riskLevel: riskLevel,
      requiresConfirmation: requiresConfirmation,
      status: status ?? this.status,
      resultMessage: resultMessage ?? this.resultMessage,
      resultData: resultData ?? this.resultData,
      createdAt: createdAt,
    );
  }
}

class AutomationFeatureFlags {
  const AutomationFeatureFlags({
    this.appsAndSettingsEnabled = true,
    this.commsEnabled = true,
    this.alarmsAndFilesEnabled = true,
  });

  final bool appsAndSettingsEnabled;
  final bool commsEnabled;
  final bool alarmsAndFilesEnabled;

  AutomationFeatureFlags copyWith({
    bool? appsAndSettingsEnabled,
    bool? commsEnabled,
    bool? alarmsAndFilesEnabled,
  }) {
    return AutomationFeatureFlags(
      appsAndSettingsEnabled:
          appsAndSettingsEnabled ?? this.appsAndSettingsEnabled,
      commsEnabled: commsEnabled ?? this.commsEnabled,
      alarmsAndFilesEnabled:
          alarmsAndFilesEnabled ?? this.alarmsAndFilesEnabled,
    );
  }
}
