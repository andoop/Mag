import 'dart:convert';

const String _kDebugTraceTag = 'PERFDBG';
const String _kDebugTraceSessionId = '28850c';

void debugTrace({
  required String runId,
  required String hypothesisId,
  required String location,
  required String message,
  required Map<String, dynamic> data,
}) {
  final payload = {
    'sessionId': _kDebugTraceSessionId,
    'runId': runId,
    'hypothesisId': hypothesisId,
    'location': location,
    'message': message,
    'data': data,
    'timestamp': DateTime.now().millisecondsSinceEpoch,
  };
  // ignore: avoid_print
  print('[$_kDebugTraceTag][$_kDebugTraceSessionId] ${jsonEncode(payload)}');
}
