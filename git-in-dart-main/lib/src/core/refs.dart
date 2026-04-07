/// Reference (branch/tag) management
library;

import 'dart:io';
import '../exceptions/git_exceptions.dart';

/// Manages git references (branches, tags, HEAD)
class RefManager {
  final String gitDir;

  const RefManager(this.gitDir);

  /// Get path to refs directory
  String get refsDir => '$gitDir/refs';

  /// Get path to heads directory (branches)
  String get headsDir => '$refsDir/heads';

  /// Get path to tags directory
  String get tagsDir => '$refsDir/tags';

  /// Get path to HEAD file
  String get headPath => '$gitDir/HEAD';

  /// Read HEAD reference
  Future<String> readHead() async {
    final file = File(headPath);
    if (!await file.exists()) {
      throw RepositoryNotFoundException(gitDir);
    }

    final content = await file.readAsString();
    final trimmed = content.trim();

    // Symbolic ref: "ref: refs/heads/main"
    if (trimmed.startsWith('ref: ')) {
      final refPath = trimmed.substring(5);
      return await _resolveRef(refPath);
    }

    // Direct hash
    return trimmed;
  }

  /// Get current branch name (or null if detached HEAD)
  Future<String?> getCurrentBranch() async {
    final file = File(headPath);
    if (!await file.exists()) {
      return null;
    }

    final content = await file.readAsString();
    final trimmed = content.trim();

    if (trimmed.startsWith('ref: refs/heads/')) {
      return trimmed.substring(16);
    }

    return null; // Detached HEAD
  }

  /// Check if HEAD is detached
  Future<bool> isDetachedHead() async {
    return await getCurrentBranch() == null;
  }

  /// Update HEAD to point to a branch
  Future<void> updateHead(String branch, {bool symbolic = true}) async {
    final file = File(headPath);
    await file.parent.create(recursive: true);

    if (symbolic) {
      await file.writeAsString('ref: refs/heads/$branch\n');
    } else {
      // Write hash directly (detached HEAD)
      await file.writeAsString('$branch\n');
    }
  }

  /// Resolve a ref to its commit hash
  Future<String> _resolveRef(String refPath) async {
    final file = File('$gitDir/$refPath');

    if (!await file.exists()) {
      throw ReferenceNotFoundException(refPath);
    }

    final content = await file.readAsString();
    final trimmed = content.trim();

    // Follow symbolic refs
    if (trimmed.startsWith('ref: ')) {
      return await _resolveRef(trimmed.substring(5));
    }

    return trimmed;
  }

  /// Read a branch reference
  Future<String> readBranch(String branch) async {
    return await _resolveRef('refs/heads/$branch');
  }

  /// Write a branch reference
  Future<void> writeBranch(String branch, String hash) async {
    final path = '$headsDir/$branch';
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString('$hash\n');
  }

  /// Delete a branch reference
  Future<void> deleteBranch(String branch) async {
    final path = '$headsDir/$branch';
    final file = File(path);

    if (!await file.exists()) {
      throw ReferenceNotFoundException('refs/heads/$branch');
    }

    await file.delete();

    // Clean up empty parent directories
    await _cleanupEmptyDirs(file.parent);
  }

  /// List all branches
  Future<List<String>> listBranches() async {
    final branches = <String>[];
    final headsDirectory = Directory(headsDir);

    if (!await headsDirectory.exists()) {
      return branches;
    }

    await for (final entity in headsDirectory.list(recursive: true)) {
      if (entity is File) {
        final relativePath = entity.path.substring(headsDir.length + 1);
        branches.add(relativePath);
      }
    }

    return branches;
  }

  /// Check if branch exists
  Future<bool> branchExists(String branch) async {
    final path = '$headsDir/$branch';
    return await File(path).exists();
  }

  /// Read a tag reference
  Future<String> readTag(String tag) async {
    return await _resolveRef('refs/tags/$tag');
  }

  /// Write a tag reference
  Future<void> writeTag(String tag, String hash) async {
    final path = '$tagsDir/$tag';
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString('$hash\n');
  }

  /// Delete a tag reference
  Future<void> deleteTag(String tag) async {
    final path = '$tagsDir/$tag';
    final file = File(path);

    if (!await file.exists()) {
      throw ReferenceNotFoundException('refs/tags/$tag');
    }

    await file.delete();
    await _cleanupEmptyDirs(file.parent);
  }

  /// List all tags
  Future<List<String>> listTags() async {
    final tags = <String>[];
    final tagsDirectory = Directory(tagsDir);

    if (!await tagsDirectory.exists()) {
      return tags;
    }

    await for (final entity in tagsDirectory.list(recursive: true)) {
      if (entity is File) {
        final relativePath = entity.path.substring(tagsDir.length + 1);
        tags.add(relativePath);
      }
    }

    return tags;
  }

  /// Clean up empty parent directories
  Future<void> _cleanupEmptyDirs(Directory dir) async {
    if (!await dir.exists()) return;

    final isEmpty = await dir.list().isEmpty;
    if (isEmpty && dir.path != refsDir) {
      await dir.delete();
      await _cleanupEmptyDirs(dir.parent);
    }
  }

  /// Get the commit hash that HEAD points to
  Future<String> resolveHead() async {
    return await readHead();
  }

  /// Get the commit hash that a ref points to
  Future<String> resolveRef(String ref) async {
    // Handle full refs
    if (ref.startsWith('refs/')) {
      return await _resolveRef(ref);
    }

    // Try as branch
    try {
      return await readBranch(ref);
    } catch (_) {}

    // Try as tag
    try {
      return await readTag(ref);
    } catch (_) {}

    // Treat as direct hash
    if (RegExp(r'^[0-9a-f]{40}$').hasMatch(ref)) {
      return ref;
    }

    throw ReferenceNotFoundException(ref);
  }
}
