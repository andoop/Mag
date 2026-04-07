# SSH Implementation Guide

## Overview

As of version 0.1.2, `git_on_dart` includes full SSH support for push and pull operations using the `dartssh2` package. This enables secure, key-based authentication for remote Git operations.

## Features

- ✅ SSH key-based authentication (RSA, ECDSA, Ed25519)
- ✅ Optional passphrase support for encrypted keys
- ✅ Both URL formats: `git@host:path` and `ssh://user@host/path`
- ✅ Automatic key file validation
- ✅ Comprehensive error handling

## Setup

### 1. Generate SSH Key (if you don't have one)

```bash
# Generate Ed25519 key (recommended)
ssh-keygen -t ed25519 -C "your_email@example.com"

# Or RSA key
ssh-keygen -t rsa -b 4096 -C "your_email@example.com"
```

### 2. Add Public Key to Git Provider

**GitHub:**
1. Copy your public key: `cat ~/.ssh/id_ed25519.pub`
2. Go to Settings → SSH and GPG keys → New SSH key
3. Paste your public key and save

**GitLab:**
1. Copy your public key: `cat ~/.ssh/id_ed25519.pub`
2. Go to Preferences → SSH Keys
3. Paste your public key and save

**Bitbucket:**
1. Copy your public key: `cat ~/.ssh/id_ed25519.pub`
2. Go to Personal settings → SSH keys → Add key
3. Paste your public key and save

## Usage

### Basic SSH Authentication

```dart
import 'package:git_on_dart/git_on_dart.dart';

// Create SSH credentials
final sshCreds = SshCredentials(
  privateKeyPath: '~/.ssh/id_ed25519',  // or id_rsa, id_ecdsa
  passphrase: null,  // Set if your key has a passphrase
);

// Verify key exists
if (!await sshCreds.hasPrivateKey()) {
  throw Exception('SSH key not found!');
}
```

### Fetch via SSH

```dart
final fetchOp = FetchOperation(repo);
final fetchResult = await fetchOp.fetch(
  'origin',
  credentials: sshCreds,
);

if (fetchResult.success) {
  print('Updated refs: ${fetchResult.updatedRefs}');
} else {
  print('Error: ${fetchResult.error}');
}
```

### Push via SSH

```dart
final pushOp = PushOperation(repo);
final pushResult = await pushOp.push(
  'origin',
  credentials: sshCreds,
  refspec: 'main:main',
  force: false,
);

if (pushResult.success) {
  print('Push successful!');
} else {
  print('Error: ${pushResult.error}');
}
```

### Pull via SSH

```dart
final pullOp = PullOperation(repo);
final pullResult = await pullOp.pull(
  'origin',
  credentials: sshCreds,
  branch: 'main',
);

if (pullResult.success) {
  print('Pull successful!');
} else {
  print('Error: ${pullResult.error}');
}
```

## SSH URL Formats

Both formats are supported:

### Format 1: `git@host:path` (GitHub style)
```dart
await remoteManager.addRemote(
  'origin',
  'git@github.com:username/repo.git',
);
```

### Format 2: `ssh://user@host/path` (Standard SSH URL)
```dart
await remoteManager.addRemote(
  'origin',
  'ssh://git@github.com/username/repo.git',
);
```

## Mobile Considerations

### Android

1. **Key Storage**: Store SSH keys in app's private directory
```dart
import 'package:path_provider/path_provider.dart';

final appDir = await getApplicationSupportDirectory();
final keyPath = '${appDir.path}/.ssh/id_ed25519';

final sshCreds = SshCredentials(
  privateKeyPath: keyPath,
);
```

2. **Permissions**: No special Android permissions required for SSH

3. **Key Generation**: Use a Dart SSH library or native code to generate keys

### iOS

1. **Key Storage**: Store in app's Documents or Application Support directory
```dart
final appDir = await getApplicationDocumentsDirectory();
final keyPath = '${appDir.path}/.ssh/id_ed25519';
```

2. **Keychain**: Consider using iOS Keychain for secure key storage

3. **Background Operations**: SSH operations work in background tasks

## Security Best Practices

### 1. Secure Key Storage
```dart
// ✅ Good: Store in app-private directory
final appDir = await getApplicationSupportDirectory();
final keyPath = '${appDir.path}/.ssh/private_key';

// ❌ Bad: Don't store in external/shared storage
// final keyPath = '/sdcard/my_key';
```

### 2. Key Validation
```dart
// Always verify key exists before operations
if (!await sshCreds.hasPrivateKey()) {
  throw Exception('SSH key missing');
}
```

### 3. Error Handling
```dart
try {
  final result = await pushOp.push(
    'origin',
    credentials: sshCreds,
  );
  
  if (!result.success) {
    // Handle operation failure
    print('Push failed: ${result.error}');
  }
} on GitException catch (e) {
  // Handle Git-specific errors
  print('Git error: ${e.message}');
} catch (e) {
  // Handle unexpected errors
  print('Unexpected error: $e');
}
```

### 4. Passphrase Security
```dart
// Don't hardcode passphrases
// ❌ Bad
const passphrase = 'my_secret_password';

// ✅ Good: Get from secure storage or user input
final passphrase = await secureStorage.read(key: 'ssh_passphrase');

final sshCreds = SshCredentials(
  privateKeyPath: keyPath,
  passphrase: passphrase,
);
```

## Troubleshooting

### "SSH key not found"
- Verify the path is correct and absolute
- Check file permissions (readable by app)
- Ensure key file exists: `await File(keyPath).exists()`

### "SSH connection timeout"
- Check network connectivity
- Verify firewall/proxy settings
- Try increasing timeout (feature coming soon)

### "Authentication failed"
- Ensure public key is added to Git provider
- Verify private key format is PEM
- Check passphrase if key is encrypted
- Confirm username in URL (usually `git`)

### "Permission denied (publickey)"
- Public key not added to Git provider
- Wrong private key being used
- Key not in PEM format

## Implementation Details

### Architecture

The SSH implementation uses:
- **dartssh2**: SSH client library for Dart
- **SSHSocket**: TCP connection to SSH server
- **SSHClient**: SSH session management
- **git-upload-pack**: Git protocol for fetch operations
- **git-receive-pack**: Git protocol for push operations

### Data Flow

#### Fetch Operation
1. Parse SSH URL (host, port, path, username)
2. Read private key from file
3. Create SSH socket connection
4. Authenticate with key pair
5. Execute `git-upload-pack <path>`
6. Parse refs from output
7. Update local remote refs
8. Close SSH connection

#### Push Operation
1. Parse SSH URL
2. Get current commit hash
3. Create SSH socket connection
4. Authenticate with key pair
5. Execute `git-receive-pack <path>`
6. Send push data (hash + ref)
7. Read response
8. Close SSH connection

### Limitations

- **Pack Protocol**: Uses simplified protocol (basic ref exchange)
- **Timeouts**: Fixed 30-second timeout (configurable timeout coming soon)
- **Progress**: No progress callbacks yet
- **Large Repos**: Not optimized for very large repositories

## Examples

See [example/ssh_example.dart](../example/ssh_example.dart) for a complete working example.

## Dependencies

- [dartssh2](https://pub.dev/packages/dartssh2) - SSH client implementation

## Contributing

Contributions to improve SSH support are welcome:
- Full pack protocol implementation
- Configurable timeouts
- Progress callbacks
- SSH agent support
- Known hosts verification

## License

MIT License - see [LICENSE](../LICENSE) file.
