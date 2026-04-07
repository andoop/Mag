/// Result wrapper for git operations
library;

/// Represents the result of a git operation
class GitResult<T> {
  final T? data;
  final GitError? error;
  final bool isSuccess;

  const GitResult.success(this.data)
      : error = null,
        isSuccess = true;

  const GitResult.failure(this.error)
      : data = null,
        isSuccess = false;

  /// Returns the data or throws if error
  T get value {
    if (isSuccess && data != null) {
      return data!;
    }
    throw error ?? Exception('No data available');
  }

  /// Returns the data or a default value
  T valueOr(T defaultValue) {
    return isSuccess && data != null ? data! : defaultValue;
  }

  /// Transform the success value
  GitResult<R> map<R>(R Function(T) transform) {
    if (isSuccess && data != null) {
      return GitResult.success(transform(data as T));
    }
    return GitResult.failure(error);
  }
}

/// Error information for failed operations
class GitError {
  final String message;
  final String? details;
  final StackTrace? stackTrace;

  const GitError(this.message, {this.details, this.stackTrace});

  @override
  String toString() {
    if (details != null) {
      return 'GitError: $message\n$details';
    }
    return 'GitError: $message';
  }
}

/// Progress event for long-running operations
class ProgressEvent {
  final String stage;
  final double percent;
  final String? message;

  const ProgressEvent({
    required this.stage,
    required this.percent,
    this.message,
  });

  @override
  String toString() {
    final pct = (percent * 100).toStringAsFixed(1);
    return '[$stage] $pct%${message != null ? ' - $message' : ''}';
  }
}
