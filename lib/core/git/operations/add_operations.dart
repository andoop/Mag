/// Add operation - stage files for commit
library;

import 'dart:io';
import 'package:path/path.dart' as p;
import '../core/repository.dart';
import '../core/index.dart';
import '../exceptions/git_exceptions.dart';

/// Add files to staging area
class AddOperation {
  final GitRepository repo;

  AddOperation(this.repo);

  /// Add files to index
  Future<void> add(List<String> paths) async {
    for (final path in paths) {
      await _addPath(path);
    }
  }

  /// Add all modified and untracked files
  Future<void> addAll() async {
    final files = await _listWorkingTreeFiles();
    await add(files);

    final indexEntries = await repo.index.read();
    final existingPaths = files.toSet();
    for (final entry in indexEntries) {
      if (!existingPaths.contains(entry.path)) {
        await repo.index.removeEntry(entry.path);
      }
    }
  }

  /// Add a single path (file or directory)
  Future<void> _addPath(String path) async {
    final absPath = p.isAbsolute(path) ? path : repo.getWorkPath(path);
    if (!_isPathWithinRepo(absPath)) {
      throw GitException('Path is outside the repository: $path');
    }
    final entity = await FileSystemEntity.type(absPath);
    final relativePath = p.isAbsolute(path) ? repo.getRelativePath(absPath) : path;

    if (entity == FileSystemEntityType.notFound) {
      final indexEntries = await repo.index.read();
      final isTracked = indexEntries.any((entry) => entry.path == relativePath);
      if (isTracked) {
        await repo.index.removeEntry(relativePath);
        return;
      }
      throw FileSystemException('File not found: $path');
    }

    if (entity == FileSystemEntityType.directory) {
      await _addDirectory(absPath);
    } else if (entity == FileSystemEntityType.file) {
      await _addFile(absPath);
    }
  }

  /// Add a single file to index
  Future<void> _addFile(String absPath) async {
    // Skip .git directory
    if (_isGitInternalPath(absPath)) {
      return;
    }

    final file = File(absPath);
    if (!await file.exists()) {
      throw FileSystemException('File not found: $absPath');
    }

    // Read file content
    final content = await file.readAsBytes();

    // Write blob to object database
    final hash = await repo.objects.writeBlob(content);

    // Get file stats
    final stat = await file.stat();

    // Get relative path
    final relativePath = repo.getRelativePath(absPath);

    // Create index entry
    final entry = await IndexEntry.fromFile(relativePath, hash, stat);

    // Add to index
    await repo.index.addEntry(entry);
  }

  /// Add all files in a directory
  Future<void> _addDirectory(String dirPath) async {
    final dir = Directory(dirPath);

    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        // Skip .git directory
        if (!_isGitInternalPath(entity.path)) {
          await _addFile(entity.path);
        }
      }
    }
  }

  /// List all files in working tree (excluding .git)
  Future<List<String>> _listWorkingTreeFiles() async {
    final files = <String>[];
    final dir = Directory(repo.workDir);

    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        final relativePath = repo.getRelativePath(entity.path);
        if (!_isGitInternalPath(entity.path) && !_isGitRelativePath(relativePath)) {
          files.add(relativePath);
        }
      }
    }

    files.sort();
    return files;
  }

  /// Remove file from index
  Future<void> remove(String path) async {
    if (p.isAbsolute(path) && !_isPathWithinRepo(path)) {
      throw GitException('Path is outside the repository: $path');
    }
    final relativePath = p.isAbsolute(path) ? repo.getRelativePath(path) : path;
    await repo.index.removeEntry(relativePath);
  }

  bool _isGitInternalPath(String path) {
    final normalized = p.normalize(path);
    return p.split(normalized).contains('.git');
  }

  bool _isGitRelativePath(String path) {
    final normalized = p.normalize(path);
    return p.split(normalized).contains('.git');
  }

  bool _isPathWithinRepo(String path) {
    final normalized = p.normalize(path);
    return normalized == repo.workDir || p.isWithin(repo.workDir, normalized);
  }
}
