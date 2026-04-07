/// Git tree object (directory listing)
library;

import 'dart:convert';
import 'dart:typed_data';
import 'git_object.dart';

/// File mode in git tree
enum GitFileMode {
  /// Directory (040000)
  directory('040000', 16384), // 0o040000

  /// Regular non-executable file (100644)
  regularFile('100644', 33188), // 0o100644

  /// Regular executable file (100755)
  executableFile('100755', 33261), // 0o100755

  /// Symbolic link (120000)
  symlink('120000', 40960), // 0o120000

  /// Gitlink (submodule) (160000)
  gitlink('160000', 57344); // 0o160000

  final String octalString;
  final int value;

  const GitFileMode(this.octalString, this.value);

  static GitFileMode fromOctal(String octal) {
    return values.firstWhere((m) => m.octalString == octal,
        orElse: () => throw ArgumentError('Invalid file mode: $octal'));
  }

  static GitFileMode fromInt(int mode) {
    return values.firstWhere((m) => m.value == mode,
        orElse: () => throw ArgumentError('Invalid file mode: $mode'));
  }
}

/// Entry in a tree object
class TreeEntry {
  final GitFileMode mode;
  final String name;
  final String hash;

  const TreeEntry({
    required this.mode,
    required this.name,
    required this.hash,
  });

  /// Check if this entry is a directory
  bool get isDirectory => mode == GitFileMode.directory;

  /// Check if this entry is a file
  bool get isFile =>
      mode == GitFileMode.regularFile || mode == GitFileMode.executableFile;

  /// Compare for sorting (directories treated as "name/" for sorting)
  int compareTo(TreeEntry other) {
    final thisName = isDirectory ? '$name/' : name;
    final otherName = other.isDirectory ? '${other.name}/' : other.name;
    return thisName.compareTo(otherName);
  }

  @override
  String toString() =>
      '${mode.octalString} ${isDirectory ? 'tree' : 'blob'} $hash\t$name';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TreeEntry &&
        other.mode == mode &&
        other.name == name &&
        other.hash == hash;
  }

  @override
  int get hashCode => Object.hash(mode, name, hash);
}

/// Represents a tree object (directory listing)
class GitTree extends GitObject {
  /// List of entries in this tree
  final List<TreeEntry> entries;

  GitTree({
    required String hash,
    required this.entries,
  }) : super(hash);

  /// Parse tree from raw bytes
  factory GitTree.parse({
    required String hash,
    required Uint8List data,
  }) {
    final entries = <TreeEntry>[];
    var offset = 0;

    while (offset < data.length) {
      // Find space after mode
      var spaceIdx = offset;
      while (spaceIdx < data.length && data[spaceIdx] != 0x20) {
        spaceIdx++;
      }
      if (spaceIdx >= data.length) break;

      final modeStr = utf8.decode(data.sublist(offset, spaceIdx));
      offset = spaceIdx + 1;

      // Find null terminator after name
      var nullIdx = offset;
      while (nullIdx < data.length && data[nullIdx] != 0x00) {
        nullIdx++;
      }
      if (nullIdx >= data.length) break;

      final name = utf8.decode(data.sublist(offset, nullIdx));
      offset = nullIdx + 1;

      // Read 20-byte SHA-1
      if (offset + 20 > data.length) break;
      final hashBytes = data.sublist(offset, offset + 20);
      final hash =
          hashBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      offset += 20;

      entries.add(TreeEntry(
        mode: GitFileMode.fromOctal(modeStr),
        name: name,
        hash: hash,
      ));
    }

    return GitTree(hash: hash, entries: entries);
  }

  /// Create tree from entries (will sort them)
  factory GitTree.create({
    required String hash,
    required List<TreeEntry> entries,
  }) {
    // Sort entries by name (with directory suffix)
    final sorted = List<TreeEntry>.from(entries)
      ..sort((a, b) => a.compareTo(b));
    return GitTree(hash: hash, entries: sorted);
  }

  @override
  GitObjectType get type => GitObjectType.tree;

  @override
  Uint8List serialize() {
    final result = BytesBuilder();

    for (final entry in entries) {
      // Write mode and space
      result.add(utf8.encode(entry.mode.octalString));
      result.addByte(0x20); // space

      // Write name and null
      result.add(utf8.encode(entry.name));
      result.addByte(0x00); // null terminator

      // Write 20-byte SHA-1 (binary)
      final hashBytes = _hexToBytes(entry.hash);
      result.add(hashBytes);
    }

    return result.toBytes();
  }

  /// Convert hex string to bytes
  static Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return result;
  }

  /// Find an entry by name
  TreeEntry? findEntry(String name) {
    return entries.where((e) => e.name == name).firstOrNull;
  }

  /// Get all file entries (excluding directories)
  List<TreeEntry> get files => entries.where((e) => e.isFile).toList();

  /// Get all directory entries
  List<TreeEntry> get directories =>
      entries.where((e) => e.isDirectory).toList();

  @override
  String toString() => 'tree $hash (${entries.length} entries)';
}
