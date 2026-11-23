import 'dart:convert';

/// Incrementally parses Server-Sent Events (`data: ...`) from byte chunks.
class SseEventDecoder {
  String _buffer = '';

  List<String> addChunk(List<int> bytes) {
    _buffer += utf8.decode(bytes, allowMalformed: true);
    final events = <String>[];

    while (true) {
      final separatorIndex = _findSeparator(_buffer);
      if (separatorIndex.index == -1) break;

      final rawBlock = _buffer.substring(0, separatorIndex.index);
      _buffer = _buffer.substring(separatorIndex.index + separatorIndex.length);

      final data = _extractDataPayload(rawBlock);
      if (data != null) {
        events.add(data);
      }
    }
    return events;
  }

  List<String> flush() {
    if (_buffer.trim().isEmpty) {
      _buffer = '';
      return const [];
    }
    final data = _extractDataPayload(_buffer);
    _buffer = '';
    return data != null ? [data] : const [];
  }

  ({int index, int length})? _findSeparatorOrNull(String text) {
    final lf = text.indexOf('\n\n');
    final crlf = text.indexOf('\r\n\r\n');
    if (lf == -1 && crlf == -1) return null;
    if (lf != -1 && (crlf == -1 || lf < crlf)) {
      return (index: lf, length: 2);
    }
    return (index: crlf, length: 4);
  }

  ({int index, int length}) _findSeparator(String text) {
    return _findSeparatorOrNull(text) ?? (index: -1, length: 0);
  }

  String? _extractDataPayload(String rawBlock) {
    final lines = rawBlock.split(RegExp(r'\r?\n'));
    final dataLines = <String>[];
    for (final line in lines) {
      if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trimLeft());
      }
    }
    if (dataLines.isEmpty) return null;
    return dataLines.join('\n');
  }
}
