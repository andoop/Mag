/// Pure Dart git implementation for Flutter
///
/// Provides local and remote git operations compatible with standard git format.
/// Optimized for mobile (Android/iOS) with memory-efficient streaming,
/// async operations, and platform-aware file handling.
library git_on_dart;

// Core repository
export 'src/core/repository.dart' show GitRepository;

// Models
export 'src/models/git_object.dart' show GitObject, GitObjectType;
export 'src/models/blob.dart' show GitBlob;
export 'src/models/tree.dart' show GitTree, TreeEntry, GitFileMode;
export 'src/models/commit.dart' show GitCommit;
export 'src/models/git_author.dart' show GitAuthor;
export 'src/models/git_result.dart' show GitResult, GitError, ProgressEvent;

// Operations
export 'src/operations/add_operations.dart' show AddOperation;
export 'src/operations/commit_operations.dart' show CommitOperation;
export 'src/operations/status_operations.dart'
    show StatusOperation, RepositoryStatus, StatusEntry, FileStatus;
export 'src/operations/checkout_operations.dart' show CheckoutOperation;
export 'src/operations/log_operations.dart' show LogOperation, LogOptions;
export 'src/operations/merge_operations.dart'
    show MergeOperation, MergeResult, FileMergeResult;
export 'src/operations/rebase_operations.dart'
    show RebaseOperation, RebaseResult, RebaseCommand, ChangeType, TreeChange;

// Remote operations
export 'src/remote/remote_manager.dart'
    show Remote, RemoteManager, Credentials, HttpsCredentials, SshCredentials;
export 'src/remote/fetch_operations.dart' show FetchOperation, FetchResult;
export 'src/remote/push_operations.dart' show PushOperation, PushResult;
export 'src/remote/pull_operations.dart' show PullOperation, PullResult;
export 'src/remote/clone_operations.dart'
    show CloneOperation, CloneResult, CloneProgress, ProgressCallback;

// Exceptions
export 'src/exceptions/git_exceptions.dart'
    show
        GitException,
        RepositoryNotFoundException,
        InvalidObjectException,
        ReferenceNotFoundException,
        MergeConflictException,
        DirtyWorkingTreeException,
        InvalidIndexException,
        FileSystemException,
        InvalidConfigException,
        OperationCancelledException;
