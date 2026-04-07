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
    final absolutePath = p.absolute(path);
    var currentDir = absolutePath;
    final type = await FileSystemEntity.type(absolutePath);
    if (type == FileSystemEntityType.file) {
      currentDir = p.dirname(absolutePath);
    }
    String? gitDir;
    String? workDir;

    // Search for a working-tree repository first.
    while (true) {
      final candidateGit = p.join(currentDir, '.git');
      final resolvedGitDir = await _resolveGitDir(candidateGit);
      if (resolvedGitDir != null) {
        gitDir = resolvedGitDir;
        workDir = currentDir;
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
      final bareGitDir = await _resolveBareGitDir(absolutePath);
      if (bareGitDir != null) {
        gitDir = bareGitDir;
        workDir = bareGitDir;
      }
    }

    if (gitDir == null || workDir == null) {
      throw RepositoryNotFoundException(path);
    }

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

  /// Resolve a branch, tag, full hash, or unique abbreviated hash.
  Future<String> resolveCommitish(String ref) async {
    final trimmed = ref.trim();
    if (trimmed.isEmpty) {
      throw const ReferenceNotFoundException('');
    }

    try {
      return await refs.resolveRef(trimmed);
    } on ReferenceNotFoundException {
      final resolved = await objects.resolvePrefix(trimmed);
      if (resolved != null) {
        final object = await objects.readObject(resolved);
        if (object is GitCommit) {
          return resolved;
        }
      }
      rethrow;
    }
  }

  /// Create a new branch
  Future<void> createBranch(String name, {String? startPoint}) async {
    if (await refs.branchExists(name)) {
      throw GitException('Branch already exists: $name');
    }

    final hash = startPoint != null
        ? await resolveCommitish(startPoint)
        : await refs.resolveHead();
    await refs.writeBranch(name, hash);
  }

  /// Delete a branch
  Future<void> deleteBranch(String name, {bool force = false}) async {
    final current = await getCurrentBranch();
    if (current == name) {
      throw GitException('Cannot delete current branch: $name');
    }

    if (!force) {
      final currentCommit = await getCurrentCommit();
      if (currentCommit == null) {
        throw GitException(
          'Cannot delete branch $name safely before the current branch has any commits',
        );
      }

      final branchCommit = await refs.readBranch(name);
      final isMerged = await isAncestorCommit(
        ancestorHash: branchCommit,
        descendantHash: currentCommit,
      );
      if (!isMerged) {
        throw GitException(
          'The branch $name is not fully merged. Use force to delete it.',
        );
      }
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
    return abs == workDir || p.isWithin(workDir, abs);
  }

  Future<bool> isAncestorCommit({
    required String ancestorHash,
    required String descendantHash,
  }) async {
    if (ancestorHash == descendantHash) {
      return true;
    }

    final visited = <String>{};
    final queue = <String>[descendantHash];
    while (queue.isNotEmpty) {
      final hash = queue.removeLast();
      if (!visited.add(hash)) {
        continue;
      }
      final commit = await readCommit(hash);
      for (final parent in commit.parents) {
        if (parent == ancestorHash) {
          return true;
        }
        queue.add(parent);
      }
    }
    return false;
  }

  static Future<String?> _resolveGitDir(String candidateGit) async {
    if (await Directory(candidateGit).exists()) {
      return candidateGit;
    }

    final gitFile = File(candidateGit);
    if (!await gitFile.exists()) {
      return null;
    }

    final content = (await gitFile.readAsString()).trim();
    const prefix = 'gitdir:';
    if (!content.startsWith(prefix)) {
      return null;
    }

    final relativePath = content.substring(prefix.length).trim();
    return p.normalize(
      p.isAbsolute(relativePath)
          ? relativePath
          : p.join(p.dirname(candidateGit), relativePath),
    );
  }

  static Future<String?> _resolveBareGitDir(String candidatePath) async {
    final head = File(p.join(candidatePath, 'HEAD'));
    final objects = Directory(p.join(candidatePath, 'objects'));
    final refs = Directory(p.join(candidatePath, 'refs'));
    if (await head.exists() && await objects.exists() && await refs.exists()) {
      return candidatePath;
    }
    return null;
  }
}
