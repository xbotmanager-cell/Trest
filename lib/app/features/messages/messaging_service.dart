import 'package:hey_dane/app/features/automation/domain/dane_action.dart';
import 'package:hey_dane/app/features/automation/services/action_engine.dart';

class MessagingService {
  MessagingService(this._engine);
  final ActionEngine _engine;

  DaneAction proposeComposeSms({
    required String phoneNumber,
    required String body,
  }) {
    return _engine.buildAction(
      type: DaneActionType.composeSms,
      parameters: {'phoneNumber': phoneNumber.trim(), 'body': body.trim()},
    );
  }

  DaneAction proposeSendSms({
    required String phoneNumber,
    required String body,
  }) {
    return _engine.buildAction(
      type: DaneActionType.sendSms,
      parameters: {'phoneNumber': phoneNumber.trim(), 'body': body.trim()},
    );
  }

  DaneAction proposeWhatsAppHandoff({
    required String phoneNumber,
    required String text,
  }) {
    return _engine.buildAction(
      type: DaneActionType.handoffWhatsApp,
      parameters: {'phoneNumber': phoneNumber.trim(), 'text': text.trim()},
    );
  }

  DaneAction proposeShareText(String text) {
    return _engine.buildAction(
      type: DaneActionType.shareText,
      parameters: {'text': text.trim()},
    );
  }
}
