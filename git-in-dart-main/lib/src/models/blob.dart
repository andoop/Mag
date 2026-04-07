/// Git blob object (file content)
library;

import 'dart:convert';
import 'dart:typed_data';
import 'git_object.dart';

/// Represents a blob object (file content)
class GitBlob extends GitObject {
  /// Raw file content
  final Uint8List content;

  GitBlob({
    required String hash,
    required this.content,
  }) : super(hash);

  /// Create blob from string content
  factory GitBlob.fromString({
    required String hash,
    required String content,
  }) {
    return GitBlob(
      hash: hash,
      content: Uint8List.fromList(utf8.encode(content)),
    );
  }

  /// Parse blob from raw bytes (without header)
  factory GitBlob.parse({
    required String hash,
    required Uint8List data,
  }) {
    return GitBlob(
      hash: hash,
      content: data,
    );
  }

  @override
  GitObjectType get type => GitObjectType.blob;

  @override
  Uint8List serialize() => content;

  /// Get content as string (assumes UTF-8)
  String get contentAsString => utf8.decode(content);

  /// Get content size in bytes
  int get size => content.length;

  @override
  String toString() => 'blob $hash ($size bytes)';
}
