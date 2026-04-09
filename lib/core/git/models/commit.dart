library;
import 'git_author.dart';

class GitCommit {
  final String hash;
  final String tree;
  final List<String> parents;
  final GitAuthor author;
  final GitAuthor committer;
  final String message;

  GitCommit({
    required this.hash,
    required this.tree,
    required this.parents,
    required this.author,
    required this.committer,
    required this.message,
  });

  bool get isInitial => parents.isEmpty;
  bool get isMerge => parents.length > 1;
  String get shortMessage {
    final firstLine = message.split('\n').first;
    return firstLine.length > 50
        ? '${firstLine.substring(0, 47)}...'
        : firstLine;
  }

  @override
  String toString() => 'commit $hash\n$shortMessage';
}
