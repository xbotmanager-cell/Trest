import 'package:hey_dane/app/features/automation/domain/dane_action.dart';
import 'package:hey_dane/app/features/automation/services/action_engine.dart';

class AlarmService {
  AlarmService(this._engine);
  final ActionEngine _engine;

  DaneAction proposeAlarm({
    required int hour,
    required int minute,
    String label = 'HEY DANE Alarm',
  }) {
    return _engine.buildAction(
      type: DaneActionType.setAlarm,
      parameters: {'hour': hour, 'minute': minute, 'label': label},
    );
  }

  DaneAction proposeTimer({
    required int seconds,
    String label = 'HEY DANE Timer',
  }) {
    return _engine.buildAction(
      type: DaneActionType.setTimer,
      parameters: {'seconds': seconds, 'label': label},
    );
  }

  DaneAction proposeShowAlarms() {
    return _engine.buildAction(
      type: DaneActionType.showAlarms,
      parameters: const {},
    );
  }
}
