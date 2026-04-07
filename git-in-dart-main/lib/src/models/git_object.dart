/// Git object types and base classes
library;

import 'dart:typed_data';

/// Type of git object
enum GitObjectType {
  blob('blob'),
  tree('tree'),
  commit('commit'),
  tag('tag');

  final String value;
  const GitObjectType(this.value);

  static GitObjectType fromString(String type) {
    return values.firstWhere((t) => t.value == type,
        orElse: () => throw ArgumentError('Invalid object type: $type'));
  }
}

/// Base class for all git objects
abstract class GitObject {
  /// SHA-1 hash of this object (40 hex chars)
  final String hash;

  /// Type of git object
  GitObjectType get type;

  const GitObject(this.hash);

  /// Serialize object to bytes (without header)
  Uint8List serialize();

  /// Get the full content with header for hashing
  /// Format: "<type> <size>\0<content>"
  Uint8List getContentWithHeader() {
    final content = serialize();
    final header = '${type.value} ${content.length}\x00';
    final headerBytes = Uint8List.fromList(header.codeUnits);

    final result = Uint8List(headerBytes.length + content.length);
    result.setRange(0, headerBytes.length, headerBytes);
    result.setRange(headerBytes.length, result.length, content);

    return result;
  }

  @override
  String toString() => '${type.value} $hash';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GitObject && other.hash == hash;
  }

  @override
  int get hashCode => hash.hashCode;
}
