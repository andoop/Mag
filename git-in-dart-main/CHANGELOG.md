## 0.1.3

* **Clone Operation**: Fully implemented repository cloning functionality
* Added `CloneOperation` with support for HTTPS and SSH protocols
* Clone features: progress tracking, bare repositories, specific branch checkout, custom remote names
* Automatic tracking branch configuration after clone
* New example: `clone_example.dart` with 7 different clone scenarios
* Updated documentation with clone examples and API reference
* Fixed repository property naming consistency (`workDir`)

## 0.1.2

* **SSH Support**: Fully implemented SSH push and pull operations using `dartssh2` package
* Added SSH authentication with private key and optional passphrase support
* Supports both `git@host:path` and `ssh://user@host/path` URL formats
* New example: `ssh_example.dart` demonstrating SSH authentication
* Updated README with SSH usage examples and documentation
* Fixed UTF-8 stream decoding in SSH operations
* Improved error handling for SSH connection failures

## 0.1.0

* Initial release
* Local git operations: init, add, commit, status, checkout, branch, log, merge, rebase
* Remote operations: remote management, fetch, push, pull
* Authentication support: HTTPS (token, basic auth), SSH (key-based)
* Git-compatible binary formats: DIRC index, tree objects, SHA-1 hashing
* Mobile-optimized: streaming I/O, async operations, memory-efficient
* Full test coverage: 43 tests including local and remote operations
* Flutter-ready package structure for Android and iOS
