/// Git repository manager
library;

import 'dart:io';
import 'package:path/path.dart' as p;
import 'object_database.dart';
import 'refs.dart';
import 'config.dart';
import 'index.dart';
import '../models/commit.dart';
import '../models/tree.dart';
import '../models/blob.dart';
import '../exceptions/git_exceptions.dart';

/// Main repository class
class GitRepository {
  final String workDir;
  final String gitDir;
  late final ObjectDatabase objects;
  late final RefManager refs;
  late final Index index;
  GitConfig? _config;

  GitRepository._(this.workDir, this.gitDir) {
    objects = ObjectDatabase(gitDir);
    refs = RefManager(gitDir);
    index = Index('$gitDir/index');
  }

  /// Get configuration
  Future<GitConfig> get config async {
    _config ??= await GitConfig.load('$gitDir/config');
    return _config!;
  }

  /// Initialize a new repository
  static Future<GitRepository> init(String path, {bool bare = false}) async {
    final workDir = p.absolute(path);
    final gitDir = bare ? workDir : p.join(workDir, '.git');

    // Create directory structure
    await Directory(gitDir).create(recursive: true);
    await Directory(p.join(gitDir, 'objects')).create(recursive: true);
    await Directory(p.join(gitDir, 'refs', 'heads')).create(recursive: true);
    await Directory(p.join(gitDir, 'refs', 'tags')).create(recursive: true);

    // Create HEAD
    final headFile = File(p.join(gitDir, 'HEAD'));
    await headFile.writeAsString('ref: refs/heads/main\n');

    // Create config
    final config = GitConfig.createDefault(p.join(gitDir, 'config'));
    config.set('core', 'bare', bare);
    await config.save();

    // Create description
    final descFile = File(p.join(gitDir, 'description'));
    await descFile.writeAsString(
        'Unnamed repository; edit this file to name the repository.\n');

    // Create empty index
    final index = Index(p.join(gitDir, 'index'));
    await index.write([]);

    return GitRepository._(workDir, gitDir);
  }

  /// Open an existing repository
  static Future<GitRepository> open(String path) async {
    var currentDir = p.absolute(path);
    String? gitDir;

    // Search for .git directory
    while (true) {
      final candidateGit = p.join(currentDir, '.git');
      if (await Directory(candidateGit).exists()) {
        gitDir = candidateGit;
        break;
      }

      // Check if we're at root
      final parent = p.dirname(currentDir);
      if (parent == currentDir) {
        break;
      }
      currentDir = parent;
    }

    if (gitDir == null) {
      throw RepositoryNotFoundException(path);
    }

    final workDir = p.dirname(gitDir);
    return GitRepository._(workDir, gitDir);
  }

  /// Check if path is inside a git repository
  static Future<bool> isRepository(String path) async {
    try {
      await open(path);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Get current branch name
  Future<String?> getCurrentBranch() async {
    return await refs.getCurrentBranch();
  }

  /// Get current commit hash
  Future<String?> getCurrentCommit() async {
    try {
      return await refs.resolveHead();
    } catch (_) {
      return null; // No commits yet
    }
  }

  /// Create a new branch
  Future<void> createBranch(String name, {String? startPoint}) async {
    if (await refs.branchExists(name)) {
      throw GitException('Branch already exists: $name');
    }

    final hash = startPoint ?? await refs.resolveHead();
    await refs.writeBranch(name, hash);
  }

  /// Delete a branch
  Future<void> deleteBranch(String name) async {
    final current = await getCurrentBranch();
    if (current == name) {
      throw GitException('Cannot delete current branch: $name');
    }

    await refs.deleteBranch(name);
  }

  /// List all branches
  Future<List<String>> listBranches() async {
    return await refs.listBranches();
  }

  /// Read a commit
  Future<GitCommit> readCommit(String hash) async {
    final object = await objects.readObject(hash);
    if (object is! GitCommit) {
      throw InvalidObjectException('Expected commit, got ${object.type}');
    }
    return object;
  }

  /// Read a tree
  Future<GitTree> readTree(String hash) async {
    final object = await objects.readObject(hash);
    if (object is! GitTree) {
      throw InvalidObjectException('Expected tree, got ${object.type}');
    }
    return object;
  }

  /// Read a blob
  Future<GitBlob> readBlob(String hash) async {
    final object = await objects.readObject(hash);
    if (object is! GitBlob) {
      throw InvalidObjectException('Expected blob, got ${object.type}');
    }
    return object;
  }

  /// Get absolute path in working directory
  String getWorkPath(String relativePath) {
    return p.join(workDir, relativePath);
  }

  /// Get relative path from working directory
  String getRelativePath(String absolutePath) {
    return p.relative(absolutePath, from: workDir);
  }

  /// Check if path is in working directory
  bool isInWorkDir(String path) {
    final abs = p.absolute(path);
    return p.isWithin(workDir, abs);
  }
}
