import 'package:flutter_test/flutter_test.dart';
import 'package:hey_dane/app/features/alarms/alarm_service.dart';
import 'package:hey_dane/app/features/automation/domain/dane_action.dart';
import 'package:hey_dane/app/features/automation/services/action_engine.dart';
import 'package:hey_dane/app/features/calls/call_service.dart';
import 'package:hey_dane/app/features/files/file_service.dart';
import 'package:hey_dane/app/features/messages/messaging_service.dart';

class _FakeAutomationGateway implements NativeAutomationGateway {
  final List<(String, Map<String, dynamic>)> calls = [];
  Map<String, dynamic> nextResult = {'success': true, 'message': 'Native ok'};

  @override
  Future<Map<String, dynamic>> invokeAction(
    String method,
    Map<String, dynamic> args,
  ) async {
    calls.add((method, args));
    return nextResult;
  }

  @override
  Future<List<Map<String, String>>> listLaunchableApps() async {
    return const [
      {'label': 'Calculator', 'packageName': 'com.android.calculator2'},
    ];
  }
}

void main() {
  group('ActionEngine structured pipeline & security gates', () {
    test('rejects arbitrary shell, root, or credential keys in AI proposals', () {
      final engine = ActionEngine(gateway: _FakeAutomationGateway());

      expect(
        engine.parseProposalFromAi(
          '{"type":"launchApp","parameters":{"shell":"rm -rf /"}}',
        ),
        isNull,
      );
      expect(
        engine.parseProposalFromAi(
          '{"type":"openSystemSetting","parameters":{"password":"123"}}',
        ),
        isNull,
      );
      expect(
        engine.parseProposalFromAi(
          '{"type":"unknownAction","parameters":{"x":1}}',
        ),
        isNull,
      );
    });

    test('parses valid AI JSON proposal and classifies risk accurately', () {
      final engine = ActionEngine(gateway: _FakeAutomationGateway());

      final low = engine.parseProposalFromAi(
        '{"type":"launchApp","parameters":{"packageName":"com.android.calculator2"}}',
      );
      expect(low, isNotNull);
      expect(low!.riskLevel, ActionRiskLevel.low);
      expect(low.requiresConfirmation, isFalse);

      final high = engine.parseProposalFromAi(
        '{"type":"placeCall","parameters":{"phoneNumber":"+254700000000"}}',
      );
      expect(high, isNotNull);
      expect(high!.riskLevel, ActionRiskLevel.high);
      expect(high.requiresConfirmation, isTrue);
      expect(high.status, ActionExecutionStatus.awaitingConfirmation);
    });

    test('blocks execution without explicit user confirmation on medium/high actions',
        () async {
      final gateway = _FakeAutomationGateway();
      final engine = ActionEngine(gateway: gateway);
      final alarms = AlarmService(engine);

      final alarmAction = alarms.proposeAlarm(hour: 6, minute: 30);
      final blocked = await engine.execute(
        alarmAction,
        featureFlags: const AutomationFeatureFlags(),
        userConfirmed: false,
      );
      expect(blocked.status, ActionExecutionStatus.awaitingConfirmation);
      expect(gateway.calls, isEmpty);

      final executed = await engine.execute(
        alarmAction,
        featureFlags: const AutomationFeatureFlags(),
        userConfirmed: true,
      );
      expect(executed.status, ActionExecutionStatus.succeeded);
      expect(gateway.calls.single.$1, 'setAlarm');
    });

    test('rejects action when module toggle is disabled in Permission Center',
        () async {
      final gateway = _FakeAutomationGateway();
      final engine = ActionEngine(gateway: gateway);
      final calls = CallService(engine);

      final action = calls.proposeOpenDialer('+254700000000');
      final rejected = await engine.execute(
        action,
        featureFlags: const AutomationFeatureFlags(commsEnabled: false),
        userConfirmed: true,
      );

      expect(rejected.status, ActionExecutionStatus.rejected);
      expect(gateway.calls, isEmpty);
    });

    test('validates alarm bounds, SAF rename traversal, and HTTPS-only downloads',
        () async {
      final gateway = _FakeAutomationGateway();
      final engine = ActionEngine(gateway: gateway);
      final alarms = AlarmService(engine);
      final files = FileService(engine);
      final messages = MessagingService(engine);

      final badAlarm = await engine.execute(
        alarms.proposeAlarm(hour: 27, minute: 0),
        featureFlags: const AutomationFeatureFlags(),
        userConfirmed: true,
      );
      expect(badAlarm.status, ActionExecutionStatus.failed);

      final badRename = await engine.execute(
        files.proposeRenameFileSaf(
          uri: 'content://doc/1',
          newName: '../secret.txt',
        ),
        featureFlags: const AutomationFeatureFlags(),
        userConfirmed: true,
      );
      expect(badRename.status, ActionExecutionStatus.failed);

      final badDownload = await engine.execute(
        files.proposeHttpsDownload(
          url: 'http://insecure.example.com/a.pdf',
          fileName: 'a.pdf',
        ),
        featureFlags: const AutomationFeatureFlags(),
        userConfirmed: true,
      );
      expect(badDownload.status, ActionExecutionStatus.failed);

      final goodSms = await engine.execute(
        messages.proposeSendSms(phoneNumber: '+254700000000', body: 'Hello'),
        featureFlags: const AutomationFeatureFlags(),
        userConfirmed: true,
      );
      expect(goodSms.status, ActionExecutionStatus.succeeded);
      expect(gateway.calls.last.$1, 'sendSms');
    });
  });
}
