/// Git commit object
library;

import 'dart:convert';
import 'dart:typed_data';
import 'git_object.dart';
import 'git_author.dart';

/// Represents a commit object
class GitCommit extends GitObject {
  /// SHA-1 of the tree object
  final String tree;

  /// Parent commit hashes (empty for initial commit)
  final List<String> parents;

  /// Author information
  final GitAuthor author;

  /// Committer information
  final GitAuthor committer;

  /// Commit message
  final String message;

  GitCommit({
    required String hash,
    required this.tree,
    required this.parents,
    required this.author,
    required this.committer,
    required this.message,
  }) : super(hash);

  /// Parse commit from raw bytes
  factory GitCommit.parse({
    required String hash,
    required Uint8List data,
  }) {
    final content = utf8.decode(data);
    final lines = content.split('\n');

    String? tree;
    final parents = <String>[];
    GitAuthor? author;
    GitAuthor? committer;
    var messageStartIdx = 0;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];

      if (line.isEmpty) {
        // Empty line marks start of message
        messageStartIdx = i + 1;
        break;
      }

      if (line.startsWith('tree ')) {
        tree = line.substring(5);
      } else if (line.startsWith('parent ')) {
        parents.add(line.substring(7));
      } else if (line.startsWith('author ')) {
        author = GitAuthor.parse(line.substring(7));
      } else if (line.startsWith('committer ')) {
        committer = GitAuthor.parse(line.substring(10));
      }
    }

    if (tree == null || author == null || committer == null) {
      throw const FormatException('Invalid commit format');
    }

    final message = lines.skip(messageStartIdx).join('\n');

    return GitCommit(
      hash: hash,
      tree: tree,
      parents: parents,
      author: author,
      committer: committer,
      message: message,
    );
  }

  @override
  GitObjectType get type => GitObjectType.commit;

  @override
  Uint8List serialize() {
    final buffer = StringBuffer();

    buffer.writeln('tree $tree');

    for (final parent in parents) {
      buffer.writeln('parent $parent');
    }

    buffer.writeln('author ${author.format()}');
    buffer.writeln('committer ${committer.format()}');
    buffer.writeln();
    buffer.write(message);

    return Uint8List.fromList(utf8.encode(buffer.toString()));
  }

  /// Check if this is an initial commit (no parents)
  bool get isInitial => parents.isEmpty;

  /// Check if this is a merge commit (multiple parents)
  bool get isMerge => parents.length > 1;

  /// Get short commit message (first line)
  String get shortMessage {
    final firstLine = message.split('\n').first;
    return firstLine.length > 50
        ? '${firstLine.substring(0, 47)}...'
        : firstLine;
  }

  @override
  String toString() => 'commit $hash\n$shortMessage';
}
