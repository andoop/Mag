/// Exception types for git operations
library;

/// Base class for all git exceptions
class GitException implements Exception {
  final String message;
  final String? details;

  const GitException(this.message, [this.details]);

  @override
  String toString() {
    if (details != null) {
      return 'GitException: $message\nDetails: $details';
    }
    return 'GitException: $message';
  }
}

/// Repository not found or not initialized
class RepositoryNotFoundException extends GitException {
  const RepositoryNotFoundException(String path)
      : super('Repository not found at: $path');
}

/// Invalid git object or corrupted data
class InvalidObjectException extends GitException {
  const InvalidObjectException(super.message, [super.details]);
}

/// Reference (branch/tag) not found
class ReferenceNotFoundException extends GitException {
  const ReferenceNotFoundException(String ref)
      : super('Reference not found: $ref');
}

/// Merge conflict detected
class MergeConflictException extends GitException {
  final List<String> conflictingFiles;

  const MergeConflictException(this.conflictingFiles)
      : super('Merge conflicts detected in ${conflictingFiles.length} file(s)');
}

/// Working directory has uncommitted changes
class DirtyWorkingTreeException extends GitException {
  const DirtyWorkingTreeException()
      : super('Working directory has uncommitted changes');
}

/// Invalid index file format
class InvalidIndexException extends GitException {
  const InvalidIndexException(super.message, [super.details]);
}

/// File system operation failed
class FileSystemException extends GitException {
  const FileSystemException(super.message, [super.details]);
}

/// Invalid configuration
class InvalidConfigException extends GitException {
  const InvalidConfigException(super.message, [super.details]);
}

/// Operation was cancelled
class OperationCancelledException extends GitException {
  const OperationCancelledException()
      : super('Operation was cancelled by user');
}
