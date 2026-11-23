import 'package:hey_dane/app/features/automation/domain/dane_action.dart';
import 'package:hey_dane/app/features/automation/services/action_engine.dart';

class CallService {
  CallService(this._engine);
  final ActionEngine _engine;

  DaneAction proposeOpenDialer(String phoneNumber) {
    return _engine.buildAction(
      type: DaneActionType.openDialer,
      parameters: {'phoneNumber': phoneNumber.trim()},
    );
  }

  DaneAction proposePlaceCall(String phoneNumber) {
    return _engine.buildAction(
      type: DaneActionType.placeCall,
      parameters: {'phoneNumber': phoneNumber.trim()},
    );
  }
}
