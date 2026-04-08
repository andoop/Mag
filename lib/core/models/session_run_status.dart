part of '../models.dart';

enum SessionRunPhase { idle, busy, retry, compacting, error }

class SessionRunStatus {
  const SessionRunStatus({
    required this.phase,
    this.message,
    this.attempt,
    this.next,
  });

  const SessionRunStatus.idle()
      : phase = SessionRunPhase.idle,
        message = null,
        attempt = null,
        next = null;

  const SessionRunStatus.error(String value)
      : phase = SessionRunPhase.error,
        message = value,
        attempt = null,
        next = null;

  final SessionRunPhase phase;
  final String? message;
  final int? attempt;
  final int? next;

  bool get isBusy =>
      phase == SessionRunPhase.busy ||
      phase == SessionRunPhase.retry ||
      phase == SessionRunPhase.compacting;

  bool get isRetrying => phase == SessionRunPhase.retry;
  bool get isCompacting => phase == SessionRunPhase.compacting;
  bool get hasError =>
      phase == SessionRunPhase.error && (message?.trim().isNotEmpty ?? false);

  JsonMap toJson() => {
        'status': phase.name,
        if (message != null) 'message': message,
        if (attempt != null) 'attempt': attempt,
        if (next != null) 'next': next,
      };

  factory SessionRunStatus.fromJson(JsonMap json) {
    final raw = (json['status'] as String?) ?? SessionRunPhase.idle.name;
    final phase = SessionRunPhase.values.firstWhere(
      (item) => item.name == raw,
      orElse: () => SessionRunPhase.idle,
    );
    return SessionRunStatus(
      phase: phase,
      message: json['message'] as String?,
      attempt: (json['attempt'] as num?)?.toInt(),
      next: (json['next'] as num?)?.toInt(),
    );
  }
}
