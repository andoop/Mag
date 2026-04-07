# Publishing Guide

## Pre-Publishing Checklist

✅ **Package structure validated** - All files properly organized
✅ **All tests passing** - 43 tests (12 local + 31 remote operations)
✅ **No linter errors** - Clean `dart analyze` output
✅ **Documentation complete** - README, CHANGELOG, LICENSE, API docs
✅ **Example included** - Working example in `example/git_demo.dart`

## Before Publishing

### 1. Update Repository URLs in pubspec.yaml

Before publishing, update the repository URLs in `pubspec.yaml` to point to your actual GitHub repository:

```yaml
repository: https://github.com/YOUR_USERNAME/git-on-dart
issue_tracker: https://github.com/YOUR_USERNAME/git-on-dart/issues
```

### 2. Commit All Changes

```bash
git add .
git commit -m "Prepare for v0.1.0 release"
git tag v0.1.0
git push origin main --tags
```

### 3. Verify One More Time

```bash
dart pub publish --dry-run
```

## Publishing to pub.dev

### First-Time Setup

If this is your first time publishing to pub.dev:

1. Make sure you have a Google account
2. Visit https://pub.dev
3. Sign in with your Google account

### Publish the Package

```bash
dart pub publish
```

You'll be prompted to:
1. Review the files that will be published
2. Confirm by opening a URL in your browser
3. Authorize the publish operation

## After Publishing

1. **Verify on pub.dev**: Visit https://pub.dev/packages/git_on_dart
2. **Check the scores**: pub.dev will analyze your package and give it scores
3. **Monitor issues**: Watch your issue tracker for bug reports

## Version Updates

For future releases:

1. Update version in `pubspec.yaml`
2. Add entry to `CHANGELOG.md`
3. Commit changes
4. Create git tag: `git tag v0.x.x`
5. Push with tags: `git push origin main --tags`
6. Publish: `dart pub publish`

## Package Features

Your package includes:

- **Local Operations**: init, add, commit, status, checkout, branch, log, merge, rebase
- **Remote Operations**: remote management, fetch, push, pull
- **Authentication**: HTTPS (token, basic auth), SSH (key-based)
- **Git Compatibility**: DIRC index format, SHA-1 hashing, tree objects
- **Mobile Optimized**: Async operations, streaming I/O, memory efficient
- **Full Test Coverage**: 43 comprehensive tests

## Notes

- Package size: ~36 KB compressed
- Supports Dart SDK >=3.0.0 <4.0.0
- Compatible with Flutter for Android, iOS, Linux, macOS, Windows
- MIT License included
