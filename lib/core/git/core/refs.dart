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

  /// Get path to packed refs file
  String get packedRefsPath => '$gitDir/packed-refs';

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

    if (await file.exists()) {
      final content = await file.readAsString();
      final trimmed = content.trim();

      // Follow symbolic refs
      if (trimmed.startsWith('ref: ')) {
        return await _resolveRef(trimmed.substring(5));
      }

      return trimmed;
    }

    final packedRef = await _readPackedRef(refPath);
    if (packedRef != null) {
      return packedRef;
    }

    throw ReferenceNotFoundException(refPath);
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

    if (await file.exists()) {
      await file.delete();

      // Clean up empty parent directories
      await _cleanupEmptyDirs(file.parent);
      return;
    }

    final removedPacked = await _removePackedRef('refs/heads/$branch');
    if (!removedPacked) {
      throw ReferenceNotFoundException('refs/heads/$branch');
    }
  }

  /// List all branches
  Future<List<String>> listBranches() async {
    final branches = <String>{};
    final headsDirectory = Directory(headsDir);

    if (!await headsDirectory.exists()) {
      branches.addAll(await _listPackedRefs('refs/heads/'));
      return branches.toList()..sort();
    }

    await for (final entity in headsDirectory.list(recursive: true)) {
      if (entity is File) {
        final relativePath = entity.path.substring(headsDir.length + 1);
        branches.add(relativePath);
      }
    }

    branches.addAll(await _listPackedRefs('refs/heads/'));
    return branches.toList()..sort();
  }

  /// Check if branch exists
  Future<bool> branchExists(String branch) async {
    final path = '$headsDir/$branch';
    if (await File(path).exists()) {
      return true;
    }
    return await _readPackedRef('refs/heads/$branch') != null;
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
    final tags = <String>{};
    final tagsDirectory = Directory(tagsDir);

    if (!await tagsDirectory.exists()) {
      tags.addAll(await _listPackedRefs('refs/tags/'));
      return tags.toList()..sort();
    }

    await for (final entity in tagsDirectory.list(recursive: true)) {
      if (entity is File) {
        final relativePath = entity.path.substring(tagsDir.length + 1);
        tags.add(relativePath);
      }
    }

    tags.addAll(await _listPackedRefs('refs/tags/'));
    return tags.toList()..sort();
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

  Future<String?> _readPackedRef(String refPath) async {
    final file = File(packedRefsPath);
    if (!await file.exists()) {
      return null;
    }

    final lines = await file.readAsLines();
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#') || trimmed.startsWith('^')) {
        continue;
      }

      final firstSpace = trimmed.indexOf(' ');
      if (firstSpace <= 0) {
        continue;
      }

      final hash = trimmed.substring(0, firstSpace);
      final path = trimmed.substring(firstSpace + 1).trim();
      if (path == refPath) {
        return hash;
      }
    }

    return null;
  }

  Future<List<String>> _listPackedRefs(String prefix) async {
    final file = File(packedRefsPath);
    if (!await file.exists()) {
      return const [];
    }

    final refs = <String>[];
    final lines = await file.readAsLines();
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#') || trimmed.startsWith('^')) {
        continue;
      }

      final firstSpace = trimmed.indexOf(' ');
      if (firstSpace <= 0) {
        continue;
      }

      final path = trimmed.substring(firstSpace + 1).trim();
      if (path.startsWith(prefix)) {
        refs.add(path.substring(prefix.length));
      }
    }
    return refs;
  }

  Future<bool> _removePackedRef(String refPath) async {
    final file = File(packedRefsPath);
    if (!await file.exists()) {
      return false;
    }

    final lines = await file.readAsLines();
    var removed = false;
    final updated = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('#') &&
          !trimmed.startsWith('^') &&
          trimmed.isNotEmpty) {
        final firstSpace = trimmed.indexOf(' ');
        if (firstSpace > 0) {
          final path = trimmed.substring(firstSpace + 1).trim();
          if (path == refPath) {
            removed = true;
            continue;
          }
        }
      }
      updated.add(line);
    }

    if (!removed) {
      return false;
    }

    await file.writeAsString('${updated.join('\n')}\n');
    return true;
  }
}
