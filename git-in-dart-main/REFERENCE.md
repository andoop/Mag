# Git on Dart - Quick Reference

## Overview

Pure Dart git implementation optimized for Flutter mobile apps. Provides local git operations compatible with standard git repositories.

## Project Structure

```
git-on-dart/
├── lib/
│   ├── git_on_dart.dart          # Main export file
│   └── src/
│       ├── core/                  # Core functionality
│       │   ├── repository.dart    # Repository management
│       │   ├── object_database.dart  # Object storage
│       │   ├── index.dart         # Index/staging area
│       │   ├── refs.dart          # References (branches/tags)
│       │   └── config.dart        # Configuration parser
│       ├── models/                # Data models
│       │   ├── git_object.dart    # Base object class
│       │   ├── blob.dart          # File content
│       │   ├── tree.dart          # Directory listing
│       │   ├── commit.dart        # Commit object
│       │   ├── git_author.dart    # Author info
│       │   └── git_result.dart    # Result wrapper
│       ├── operations/            # Git operations
│       │   ├── add_operations.dart      # Stage files
│       │   ├── commit_operations.dart   # Create commits
│       │   ├── status_operations.dart   # Show status
│       │   ├── checkout_operations.dart # Switch branches
│       │   ├── log_operations.dart      # History
│       │   ├── merge_operations.dart    # Merge branches
│       │   └── rebase_operations.dart   # Rebase commits
│       └── exceptions/            # Exception types
│           └── git_exceptions.dart
├── example/
│   └── git_demo.dart             # Usage example
├── test/
│   └── git_on_dart_test.dart     # Unit tests
└── pubspec.yaml                  # Package configuration
```

## Basic Usage

### Initialize a Repository

```dart
import 'package:git_on_dart/git_on_dart.dart';

// Initialize new repository
final repo = await GitRepository.init('/path/to/repo');

// Open existing repository
final repo = await GitRepository.open('/path/to/repo');
```

### Configure User

```dart
final config = await repo.config;
config.set('user', 'name', 'Your Name');
config.set('user', 'email', 'your@email.com');
await config.save();
```

### Add Files (Stage)

```dart
final addOp = AddOperation(repo);

// Add specific files
await addOp.add(['file1.txt', 'file2.txt']);

// Add all files
await addOp.addAll();

// Remove from staging
await addOp.remove('file.txt');
```

### Commit Changes

```dart
final commitOp = CommitOperation(repo);

// Create commit
final commit = await commitOp.commit('Commit message');

// Commit with custom author
final commit = await commitOp.commit(
  'Commit message',
  author: GitAuthor(name: 'Name', email: 'email@example.com'),
);

// Amend last commit
final commit = await commitOp.amend('New message');
```

### Check Status

```dart
final statusOp = StatusOperation(repo);
final status = await statusOp.status();

print('Current branch: ${status.currentBranch}');
print('Staged files: ${status.staged.length}');
print('Unstaged changes: ${status.unstaged.length}');
print('Untracked files: ${status.untracked.length}');

// Check if clean
final isClean = status.isClean;
```

### Branch Operations

```dart
// Create branch
await repo.createBranch('feature-branch');

// List branches
final branches = await repo.listBranches();

// Get current branch
final current = await repo.getCurrentBranch();

// Delete branch
await repo.deleteBranch('old-branch');
```

### Checkout

```dart
final checkoutOp = CheckoutOperation(repo);

// Checkout branch
await checkoutOp.checkoutBranch('feature');

// Checkout specific commit (detached HEAD)
await checkoutOp.checkoutCommit(commitHash);

// Create and checkout new branch
await checkoutOp.checkoutNewBranch('new-feature');

// Restore file from HEAD
await checkoutOp.restoreFile('path/to/file.txt');
```

### View History

```dart
final logOp = LogOperation(repo);

// Get all commits
final commits = await logOp.getHistory();

// Get limited commits
final recent = await logOp.getHistory(
  options: LogOptions(maxCount: 10),
);

// Stream commits
await for (final commit in logOp.log()) {
  print('${commit.hash.substring(0, 7)} - ${commit.shortMessage}');
}

// Get commit by hash/ref
final commit = await logOp.getCommit('HEAD');
```

### Merge Branches

```dart
final mergeOp = MergeOperation(repo);

// Merge branch into current
final result = await mergeOp.merge('feature-branch');

if (result.success) {
  print('Merge successful');
} else {
  print('Conflicts in: ${result.conflicts}');
  // Resolve conflicts manually
  await mergeOp.abortMerge(); // Or abort
}
```

### Rebase

```dart
final rebaseOp = RebaseOperation(repo);

// Rebase current branch onto target
final result = await rebaseOp.rebase('main');

if (result.success) {
  print('Rebase successful');
} else {
  print('Conflicts during rebase');
}
```

## Key Features

### Git Protocol Compatibility

- **Binary Format Support**: DIRC index, packfiles, tree objects
- **SHA-1 Hashing**: Identical to standard git
- **Zlib Compression**: Standard DEFLATE compression
- **Compatible Storage**: Works with existing .git directories

### Mobile Optimization

- **Memory Efficient**: Streaming I/O for large files (64KB chunks)
- **Async Operations**: Non-blocking with async/await
- **Platform Aware**: Handles iOS/Android file system differences
- **Battery Friendly**: Batched I/O operations

### Supported Operations

✅ **Implemented:**
- `init` - Initialize repository
- `add` - Stage files
- `commit` - Create commits
- `status` - Show working tree status
- `branch` - Create/list/delete branches
- `checkout` - Switch branches/restore files
- `log` - View commit history
- `merge` - Merge branches (3-way merge)
- `rebase` - Rebase commits
- `clone` - Clone remote repository
- `fetch` - Fetch from remote
- `push` - Push to remote
- `pull` - Fetch and merge

🚧 **Not Yet Implemented:**
- `diff` - Generate diffs
- `pack` - Create packfiles

## Testing

Run tests:
```bash
dart test
```

Run example:
```bash
dart run example/git_demo.dart
```

## Integration with Flutter

### Example in Flutter App

```dart
import 'package:flutter/material.dart';
import 'package:git_on_dart/git_on_dart.dart';
import 'package:path_provider/path_provider.dart';

Future<void> initRepository() async {
  // Get app documents directory
  final docsDir = await getApplicationDocumentsDirectory();
  final repoPath = '${docsDir.path}/my_repo';
  
  // Initialize repository
  final repo = await GitRepository.init(repoPath);
  
  // Use repository...
}
```

### Using with Progress Indicators

```dart
// For long operations, wrap in compute() for isolate
Future<void> performMerge(String branch) async {
  final result = await compute(_doMerge, MergeParams(repoPath, branch));
  // Update UI with result
}

static Future<MergeResult> _doMerge(MergeParams params) async {
  final repo = await GitRepository.open(params.repoPath);
  final mergeOp = MergeOperation(repo);
  return await mergeOp.merge(params.branch);
}
```

## Architecture Notes

### Object Database
- Loose objects stored in `.git/objects/[2-char]/[38-char]`
- SHA-1 computed from `<type> <size>\0<content>`
- Zlib compression for storage
- Streaming support for large files

### Index (Staging Area)
- Binary DIRC format (Version 2)
- Big-endian integers
- 8-byte entry alignment
- SHA-1 checksum footer

### Refs (Branches/Tags)
- Text files in `.git/refs/heads/` and `.git/refs/tags/`
- HEAD can be symbolic (`ref: refs/heads/main`) or direct SHA-1
- Packed refs supported for reading

### Merge Algorithm
1. Find common ancestor (merge base)
2. Compare three trees: base, ours, theirs
3. Apply changes automatically when possible
4. Mark conflicts with standard markers

## Common Patterns

### Error Handling

```dart
try {
  final commit = await commitOp.commit('Message');
} on GitException catch (e) {
  print('Git error: ${e.message}');
} on RepositoryNotFoundException catch (e) {
  print('Repository not found: $e');
}
```

### Checking for Changes

```dart
final statusOp = StatusOperation(repo);
final isClean = await statusOp.isClean();

if (!isClean) {
  print('Uncommitted changes detected');
}
```

### Working with Commits

```dart
final logOp = LogOperation(repo);
final commit = await logOp.getCommit('HEAD');

print('Author: ${commit.author.name}');
print('Date: ${commit.author.timestamp}');
print('Message: ${commit.message}');
print('Parents: ${commit.parents}');

// Read tree
final tree = await repo.readTree(commit.tree);
for (final entry in tree.entries) {
  print('${entry.mode.octalString} ${entry.name}');
}
```

## Limitations

1. **Local Only**: No remote operations (by design)
2. **No Hooks**: Git hooks not executed
3. **Basic Merge**: Only 3-way merge (no recursive strategy)
4. **No Submodules**: Gitlinks not fully supported
5. **Mobile Focus**: Optimized for mobile, may not be optimal for desktop

## Performance Tips

1. **Use streaming for large files**: ObjectDatabase.streamObject()
2. **Batch operations**: Add multiple files at once with addAll()
3. **Limit log queries**: Use LogOptions.maxCount
4. **Monitor memory**: Keep individual operations under 50MB
5. **Use isolates**: Wrap heavy operations in compute()

## License

MIT License - See LICENSE file

## Contributing

Contributions welcome! Focus areas:
- Diff generation
- Pack file writing
- Performance optimizations
- Additional tests
- Documentation improvements
