import 'package:hey_dane/app/features/automation/domain/dane_action.dart';
import 'package:hey_dane/app/features/automation/services/action_engine.dart';

class FileService {
  FileService(this._engine);
  final ActionEngine _engine;

  DaneAction proposePickFileSaf() {
    return _engine.buildAction(
      type: DaneActionType.pickFileSaf,
      parameters: const {},
    );
  }

  DaneAction proposeRenameFileSaf({
    required String uri,
    required String newName,
  }) {
    return _engine.buildAction(
      type: DaneActionType.renameFileSaf,
      parameters: {'uri': uri.trim(), 'newName': newName.trim()},
    );
  }

  DaneAction proposeDeleteFileSaf(String uri) {
    return _engine.buildAction(
      type: DaneActionType.deleteFileSaf,
      parameters: {'uri': uri.trim()},
    );
  }

  DaneAction proposeBrowseMedia() {
    return _engine.buildAction(
      type: DaneActionType.browseMedia,
      parameters: const {},
    );
  }

  DaneAction proposeHttpsDownload({
    required String url,
    required String fileName,
  }) {
    return _engine.buildAction(
      type: DaneActionType.downloadHttps,
      parameters: {'url': url.trim(), 'fileName': fileName.trim()},
    );
  }
}
