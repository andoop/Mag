library session_engine;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'agents.dart';
import 'database.dart';
import 'debug_trace.dart';
import 'mcp_service.dart';
import 'models.dart';
import 'prompt_system.dart';
import 'skill_registry.dart';
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

const bool _kDebugEngine = true;

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

bool _isContextOverflowError(Object error) {
  final msg = error.toString().toLowerCase();
  if (msg.contains('context_length_exceeded')) return true;
  if (msg.contains('prompt is too long')) return true;
  if (msg.contains('input is too long for requested model')) return true;
  if (msg.contains('exceeds the context window')) return true;
  if (msg.contains('input token count') &&
      msg.contains('exceeds the maximum')) {
    return true;
  }
  if (msg.contains('maximum prompt length is')) return true;
  if (msg.contains('reduce the length of the messages')) return true;
  if (msg.contains('maximum context length is')) return true;
  if (msg.contains('exceeds the available context size')) return true;
  if (msg.contains('greater than the context length')) return true;
  if (msg.contains('context window exceeds limit')) return true;
  if (msg.contains('exceeded model token limit')) return true;
  if (msg.contains('request entity too large')) return true;
  if (msg.contains('context length is only')) return true;
  if (msg.contains('input length') && msg.contains('exceeds')) return true;
  if (msg.contains('prompt too long; exceeded')) return true;
  if (msg.contains('too large for model with')) return true;
  if (msg.contains('model_context_window_exceeded')) return true;
  if (msg.contains('model request failed: 413')) return true;
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

String _classifyToolError(String errorText) {
  final lower = errorText.toLowerCase();
  if (lower.contains('already exists')) return 'file_exists';
  if (lower.contains('must read')) return 'no_read';
  if (lower.contains('modified since')) return 'stale_read';
  if (lower.contains('oldstring not found') || lower.contains('not found in')) {
    return 'edit_mismatch';
  }
  if (lower.contains('changed since last read')) return 'stale_anchor';
  if (lower.contains('missing required')) return 'missing_args';
  if (lower.contains('invalid') && lower.contains('arguments')) {
    return 'invalid_args';
  }
  return 'other';
}
