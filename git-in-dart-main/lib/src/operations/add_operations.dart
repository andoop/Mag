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
  }

  /// Add a single path (file or directory)
  Future<void> _addPath(String path) async {
    final absPath = p.isAbsolute(path) ? path : repo.getWorkPath(path);
    final entity = await FileSystemEntity.type(absPath);

    if (entity == FileSystemEntityType.notFound) {
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
    if (absPath.contains('/.git/')) {
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
        if (!entity.path.contains('/.git/')) {
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
        if (!relativePath.startsWith('.git/')) {
          files.add(relativePath);
        }
      }
    }

    return files;
  }

  /// Remove file from index
  Future<void> remove(String path) async {
    final relativePath = p.isAbsolute(path) ? repo.getRelativePath(path) : path;
    await repo.index.removeEntry(relativePath);
  }
}
