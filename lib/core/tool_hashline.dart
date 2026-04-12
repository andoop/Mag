part of 'tool_runtime.dart';

class _HashlineFileEnvelope {
  _HashlineFileEnvelope({
    required this.content,
    required this.hadBom,
    required this.lineEnding,
  });

  final String content;
  final bool hadBom;
  final String lineEnding;
}

String _detectHashlineLineEnding(String content) {
  final crlfIndex = content.indexOf('\r\n');
  final lfIndex = content.indexOf('\n');
  if (lfIndex == -1) return '\n';
  if (crlfIndex == -1) return '\n';
  return crlfIndex < lfIndex ? '\r\n' : '\n';
}

_HashlineFileEnvelope _canonicalizeHashlineFileText(String content) {
  final hadBom = content.startsWith('\uFEFF');
  final withoutBom = hadBom ? content.substring(1) : content;
  return _HashlineFileEnvelope(
    content: withoutBom.replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
    hadBom: hadBom,
    lineEnding: _detectHashlineLineEnding(withoutBom),
  );
}

String _restoreHashlineFileText(
  String content,
  _HashlineFileEnvelope envelope,
) {
  final restored = envelope.lineEnding == '\r\n'
      ? content.replaceAll('\n', '\r\n')
      : content;
  return envelope.hadBom ? '\uFEFF$restored' : restored;
}
