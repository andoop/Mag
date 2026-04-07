# git_on_dart

[![pub package](https://img.shields.io/pub/v/git_on_dart.svg)](https://pub.dev/packages/git_on_dart)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![GitHub repo](https://img.shields.io/badge/GitHub-sojankreji%2Fgit--in--dart-blue.svg?logo=github)](https://github.com/sojankreji/git-in-dart)
[![GitHub issues](https://img.shields.io/github/issues/sojankreji/git-in-dart)](https://github.com/sojankreji/git-in-dart/issues)

A pure Dart implementation of Git, optimized for Flutter mobile applications (Android & iOS). Build native Git clients for mobile with full local and remote repository support.

## Features

### Local Operations
- ✅ **Repository Management**: `init`, `open`
- ✅ **Staging**: `add`, `status`
- ✅ **Commits**: `commit`, `log`
- ✅ **Branching**: create, delete, list branches
- ✅ **Checkout**: switch branches and restore files
- ✅ **Merging**: 3-way merge with conflict detection
- ✅ **Rebasing**: interactive rebase support

### Remote Operations
- ✅ **Remote Management**: add, remove, list remotes
- ✅ **Clone**: create local copy of remote repository
- ✅ **Fetch**: download refs and objects from remote
- ✅ **Push**: upload commits to remote (with force option)
- ✅ **Pull**: fetch and merge in one operation
- ✅ **Authentication**: HTTPS (token, basic auth), SSH (key-based)

### Technical Features
- 🚀 **Git Protocol Compatible**: Standard DIRC index format, SHA-1 hashing, tree objects
- 📱 **Mobile Optimized**: Memory-efficient streaming I/O, async/await throughout
- 🔒 **Type Safe**: Strong typing with comprehensive error handling via `GitResult<T>`
- ✨ **Flutter Ready**: Works seamlessly with Flutter for Android and iOS
- 🌐 **Cross-Platform**: Android, iOS, Linux, macOS, Windows

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  git_on_dart: ^0.1.0
```

Then run:
```bash
dart pub get
```

## Quick Start

### Initialize a Repository

```dart
import 'package:git_on_dart/git_on_dart.dart';

// Create a new repository
final repo = await GitRepository.init('/path/to/repo');

// Or open an existing one
final repo = await GitRepository.open('/path/to/repo');
```

### Basic Workflow

```dart
// Stage files
final addOp = AddOperation(repo);
await addOp.addFiles(['lib/main.dart', 'pubspec.yaml']);

// Check status
final statusOp = StatusOperation(repo);
final status = await statusOp.getStatus();
print('Modified: ${status.modified.length}');
print('Staged: ${status.staged.length}');

// Commit changes
final commitOp = CommitOperation(repo);
final author = GitAuthor(
  name: 'Your Name',
  email: 'your@email.com',
  timestamp: DateTime.now(),
);
final result = await commitOp.commit(
  message: 'Initial commit',
  author: author,
);
print('Commit: ${result.data}');
```

### Branching and Merging

```dart
// Create and switch to a new branch
await repo.refManager.createBranch('feature-branch');
final checkoutOp = CheckoutOperation(repo);
await checkoutOp.checkout('feature-branch');

// Make changes and commit...

// Switch back and merge
await checkoutOp.checkout('main');
final mergeOp = MergeOperation(repo);
final mergeResult = await mergeOp.merge('feature-branch');

if (mergeResult.hasConflicts) {
  print('Conflicts in: ${mergeResult.conflicts.keys}');
  // Handle conflicts...
}
```

### Remote Operations

```dart
// Clone a repository
final cloneOp = CloneOperation();
final cloneResult = await cloneOp.clone(
  url: 'https://github.com/username/repo.git',
  path: '/path/to/destination',
  credentials: HttpsCredentials.token('your_token'),
);

if (cloneResult.success) {
  print('Cloned to ${cloneResult.repository!.workDir}');
}

// Add a remote
final remoteManager = RemoteManager(repo);
await remoteManager.addRemote(
  name: 'origin',
  url: 'https://github.com/username/repo.git',
);

// Configure authentication
final credentials = HttpsCredentials.token('your_github_token');

// Push changes
final pushOp = PushOperation(repo);
final pushResult = await pushOp.push(
  remoteName: 'origin',
  refspec: 'main:main',
  credentials: credentials,
);

// Pull changes
final pullOp = PullOperation(repo);
final pullResult = await pullOp.pull(
  remoteName: 'origin',
  branch: 'main',
  credentials: credentials,
);
```

### SSH Authentication

```dart
// Using SSH keys (now fully supported!)
final sshCreds = SshCredentials(
  privateKeyPath: '/path/to/id_rsa',
  passphrase: 'optional_passphrase', // if key is encrypted
);

// Push via SSH
await pushOp.push(
  remoteName: 'origin',
  refspec: 'main:main',
  credentials: sshCreds,
);

// Fetch via SSH
final fetchOp = FetchOperation(repo);
await fetchOp.fetch(
  remoteName: 'origin',
  credentials: sshCreds,
);

// Supported SSH URL formats:
// - git@github.com:user/repo.git
// - ssh://git@github.com/user/repo.git
```

## Error Handling

All operations return `GitResult<T>` for consistent error handling:

```dart
final result = await commitOp.commit(
  message: 'My commit',
  author: author,
);

if (result.isSuccess) {
  print('Commit hash: ${result.data}');
} else {
  print('Error: ${result.error?.message}');
  print('Type: ${result.error?.type}');
}
```

## Examples

The package includes several comprehensive examples:

### [git_demo.dart](example/git_demo.dart)
Complete working example demonstrating:
- Repository initialization
- File staging and commits
- Branch management
- Merge operations
- Status checking

### [ssh_example.dart](example/ssh_example.dart)
SSH authentication examples:
- Fetch with SSH keys
- Push with SSH authentication
- Pull operations

### [clone_example.dart](example/clone_example.dart)
Repository cloning scenarios:
- Clone public repositories
- Clone with HTTPS token auth
- Clone with SSH
- Progress tracking
- Bare repositories
- Custom branch and remote names

Run examples with:
```bash
dart run example/git_demo.dart
dart run example/ssh_example.dart
dart run example/clone_example.dart
```

## Architecture

- **Core**: Repository management, object database, index, refs
- **Models**: Git objects (blob, tree, commit), authors, results
- **Operations**: Modular operations for each git command
- **Remote**: Remote repository management and network operations

For detailed implementation notes, see [IMPLEMENTATION.md](IMPLEMENTATION.md).

## Testing

The package includes comprehensive test coverage:

```bash
dart test
```

- 12 local operation tests
- 31 remote operation tests
- 6 clone operation tests
- Full workflow integration tests

## Limitations

- **Pack Protocol**: Simplified implementation for basic push/pull operations (full git pack protocol in progress)
- **Large Files**: Optimized for mobile apps; no LFS support yet
- **Advanced Features**: Stash, cherry-pick, interactive rebase, and submodules not yet implemented

## Recent Updates

### v0.1.3
- ✅ **Clone Operation**: Full repository cloning with HTTPS and SSH
- ✅ Progress tracking, bare repositories, branch selection
- ✅ Automatic tracking branch configuration
- ✅ New comprehensive clone examples

### v0.1.2
- ✅ **Full SSH Support**: Push and pull operations now work with SSH authentication via `dartssh2` package
- ✅ Supports both `git@host:path` and `ssh://user@host/path` URL formats
- ✅ SSH key-based authentication with optional passphrase support

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see [LICENSE](LICENSE) file for details.
