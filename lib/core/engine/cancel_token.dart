part of '../session_engine.dart';

/// Dart equivalent of AbortSignal/AbortController from mag.
/// Threaded through prompt → model gateway → tool execution → permission/question waits.
class CancelToken {
  final Completer<Never> _completer = Completer<Never>();
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _completer.completeError(CancelledException());
  }

  void throwIfCancelled() {
    if (_cancelled) throw CancelledException();
  }

  /// Race [future] against cancellation. Returns the result of [future]
  /// or throws [CancelledException] if cancelled first.
  Future<T> guard<T>(Future<T> future) {
    if (_cancelled) return Future.error(CancelledException());
    return Future.any<T>([future, _completer.future]);
  }
}

class CancelledException implements Exception {
  @override
  String toString() => 'Prompt was cancelled';
}
