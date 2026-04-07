library session_engine;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'agents.dart';
import 'database.dart';
import 'debug_trace.dart';
import 'models.dart';
import 'prompt_system.dart';
import 'tool_runtime.dart';
import 'workspace_bridge.dart';

part 'engine/cancel_token.dart';
part 'engine/snapshot.dart';
part 'engine/event_bus.dart';
part 'engine/permission_center.dart';
part 'engine/question_center.dart';
part 'engine/model_gateway.dart';
part 'engine/session_core.dart';
part 'engine/prompt_loop.dart';
part 'engine/summarize.dart';
part 'engine/conversation.dart';
part 'engine/tool_execution.dart';

const bool _kDebugEngine = false;

void _debugLog(String tag, String message, [JsonMap? data]) {
  if (!_kDebugEngine) return;
  // ignore: avoid_print
  print(
      '[session-engine][$tag] $message${data != null ? ' ${jsonEncode(data)}' : ''}');
}

const int _retryInitialDelayMs = 2000;
const int _retryBackoffFactor = 2;
const int _retryMaxDelayMs = 30000;
const int _maxRetryAttempts = 5;

int _retryDelay(int attempt) {
  return math.min(
    _retryInitialDelayMs * math.pow(_retryBackoffFactor, attempt - 1).toInt(),
    _retryMaxDelayMs,
  );
}

bool _isRetryableError(Object error) {
  final msg = error.toString().toLowerCase();
  if (msg.contains('429') || msg.contains('too many requests')) return true;
  if (msg.contains('overloaded') || msg.contains('rate limit')) return true;
  if (msg.contains('502') || msg.contains('503') || msg.contains('504')) {
    return true;
  }
  if (msg.contains('freeusagelimiterror')) return true;
  return false;
}

String _retryMessage(Object error) {
  final msg = error.toString().toLowerCase();
  if (msg.contains('429') ||
      msg.contains('too many requests') ||
      msg.contains('rate limit')) {
    return 'Rate limited, retrying...';
  }
  if (msg.contains('overloaded')) return 'Provider overloaded, retrying...';
  if (msg.contains('freeusagelimiterror')) {
    return 'Free usage limit, retrying...';
  }
  return 'Temporary error, retrying...';
}
