/// Pure Dart git implementation for mobile.
///
/// Local operations: init, status, add, commit, log, diff, branch, checkout, merge.
/// Based on git-in-dart, adapted for the Mag mobile agent.
library;

export 'core/repository.dart' show GitRepository;
export 'core/object_database.dart' show ObjectDatabase;
export 'core/refs.dart' show RefManager;
export 'core/config.dart' show GitConfig;
export 'core/index.dart' show IndexEntry, Index;

export 'models/git_object.dart' show GitObject, GitObjectType;
export 'models/blob.dart' show GitBlob;
export 'models/tree.dart' show GitTree, TreeEntry, GitFileMode;
export 'models/commit.dart' show GitCommit;
export 'models/git_author.dart' show GitAuthor;
export 'models/git_result.dart' show GitResult, GitError, ProgressEvent;

export 'operations/add_operations.dart' show AddOperation;
export 'operations/commit_operations.dart' show CommitOperation;
export 'operations/status_operations.dart'
    show StatusOperation, RepositoryStatus, StatusEntry, FileStatus;
export 'operations/checkout_operations.dart' show CheckoutOperation;
export 'operations/log_operations.dart' show LogOperation, LogOptions;
export 'operations/merge_operations.dart'
    show MergeOperation, MergeResult, FileMergeResult;

export 'exceptions/git_exceptions.dart';

export 'git_service.dart' show GitService;
