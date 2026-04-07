/// Object database for storing and retrieving git objects
library;

import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:archive/archive.dart';
import '../models/git_object.dart';
import '../models/blob.dart';
import '../models/tree.dart';
import '../models/commit.dart';
import '../exceptions/git_exceptions.dart';

/// Handles storage and retrieval of git objects
class ObjectDatabase {
  final String gitDir;

  const ObjectDatabase(this.gitDir);

  /// Get path to objects directory
  String get objectsDir => '$gitDir/objects';

  /// Compute SHA-1 hash of data
  static String computeHash(Uint8List data) {
    final digest = sha1.convert(data);
    return digest.toString();
  }

  /// Get path to loose object file
  String _getLooseObjectPath(String hash) {
    if (hash.length != 40) {
      throw ArgumentError('Invalid hash length: ${hash.length}');
    }
    final prefix = hash.substring(0, 2);
    final suffix = hash.substring(2);
    return '$objectsDir/$prefix/$suffix';
  }

  /// Check if object exists
  Future<bool> hasObject(String hash) async {
    final path = _getLooseObjectPath(hash);
    return await File(path).exists();
  }

  /// Write a git object to the database
  /// Returns the SHA-1 hash of the object
  Future<String> writeObject(GitObject object) async {
    final content = object.getContentWithHeader();
    final hash = computeHash(content);

    // Check if object already exists
    if (await hasObject(hash)) {
      return hash;
    }

    // Compress with zlib
    final compressed = _compress(content);

    // Write to file
    final path = _getLooseObjectPath(hash);
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(compressed);

    return hash;
  }

  /// Write raw data as a blob object
  Future<String> writeBlob(Uint8List data) async {
    // Create header
    final header = 'blob ${data.length}\x00';
    final headerBytes = Uint8List.fromList(header.codeUnits);

    // Combine header and data
    final content = Uint8List(headerBytes.length + data.length);
    content.setRange(0, headerBytes.length, headerBytes);
    content.setRange(headerBytes.length, content.length, data);

    // Compute hash
    final hash = computeHash(content);

    // Check if exists
    if (await hasObject(hash)) {
      return hash;
    }

    // Compress and write
    final compressed = _compress(content);
    final path = _getLooseObjectPath(hash);
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(compressed);

    return hash;
  }

  /// Read a git object from the database
  Future<GitObject> readObject(String hash) async {
    final path = _getLooseObjectPath(hash);
    final file = File(path);

    if (!await file.exists()) {
      throw InvalidObjectException('Object not found: $hash');
    }

    try {
      // Read and decompress
      final compressed = await file.readAsBytes();
      final decompressed = _decompress(compressed);

      // Parse header
      final nullIdx = decompressed.indexOf(0);
      if (nullIdx == -1) {
        throw const InvalidObjectException(
            'Invalid object format: no null byte');
      }

      final header = String.fromCharCodes(decompressed.sublist(0, nullIdx));
      final content = decompressed.sublist(nullIdx + 1);

      final parts = header.split(' ');
      if (parts.length != 2) {
        throw InvalidObjectException('Invalid object header: $header');
      }

      final type = parts[0];
      final size = int.parse(parts[1]);

      if (content.length != size) {
        throw InvalidObjectException(
          'Size mismatch: expected $size, got ${content.length}',
        );
      }

      // Parse based on type
      switch (type) {
        case 'blob':
          return GitBlob.parse(hash: hash, data: content);
        case 'tree':
          return GitTree.parse(hash: hash, data: content);
        case 'commit':
          return GitCommit.parse(hash: hash, data: content);
        default:
          throw InvalidObjectException('Unsupported object type: $type');
      }
    } catch (e) {
      throw InvalidObjectException('Failed to read object $hash: $e');
    }
  }

  /// Read object as raw bytes (decompressed, with header)
  Future<Uint8List> readObjectRaw(String hash) async {
    final path = _getLooseObjectPath(hash);
    final file = File(path);

    if (!await file.exists()) {
      throw InvalidObjectException('Object not found: $hash');
    }

    final compressed = await file.readAsBytes();
    return _decompress(compressed);
  }

  /// Stream large object content in chunks
  Stream<List<int>> streamObject(String hash) async* {
    final path = _getLooseObjectPath(hash);
    final file = File(path);

    if (!await file.exists()) {
      throw InvalidObjectException('Object not found: $hash');
    }

    // For loose objects, we need to decompress fully first
    // (zlib doesn't support streaming decompression easily)
    final compressed = await file.readAsBytes();
    final decompressed = _decompress(compressed);

    // Skip header
    final nullIdx = decompressed.indexOf(0);
    if (nullIdx == -1) {
      throw const InvalidObjectException('Invalid object format');
    }

    final content = decompressed.sublist(nullIdx + 1);

    // Yield in chunks
    const chunkSize = 64 * 1024; // 64KB chunks
    for (var i = 0; i < content.length; i += chunkSize) {
      final end =
          (i + chunkSize < content.length) ? i + chunkSize : content.length;
      yield content.sublist(i, end);
    }
  }

  /// Compress data using zlib (DEFLATE)
  Uint8List _compress(Uint8List data) {
    const encoder = ZLibEncoder();
    return Uint8List.fromList(encoder.encode(data));
  }

  /// Decompress zlib data
  Uint8List _decompress(Uint8List data) {
    const decoder = ZLibDecoder();
    return Uint8List.fromList(decoder.decodeBytes(data));
  }

  /// List all object hashes in the database
  Future<List<String>> listObjects() async {
    final objects = <String>[];
    final objectsDirectory = Directory(objectsDir);

    if (!await objectsDirectory.exists()) {
      return objects;
    }

    await for (final prefix in objectsDirectory.list()) {
      if (prefix is Directory) {
        final prefixName = prefix.path.split('/').last;
        if (prefixName.length == 2) {
          await for (final file in prefix.list()) {
            if (file is File) {
              final suffix = file.path.split('/').last;
              objects.add('$prefixName$suffix');
            }
          }
        }
      }
    }

    return objects;
  }

  /// Get object type without fully parsing it
  Future<GitObjectType> getObjectType(String hash) async {
    final path = _getLooseObjectPath(hash);
    final file = File(path);

    if (!await file.exists()) {
      throw InvalidObjectException('Object not found: $hash');
    }

    final compressed = await file.readAsBytes();
    final decompressed = _decompress(compressed);

    final nullIdx = decompressed.indexOf(0);
    if (nullIdx == -1) {
      throw const InvalidObjectException('Invalid object format');
    }

    final header = String.fromCharCodes(decompressed.sublist(0, nullIdx));
    final type = header.split(' ')[0];

    return GitObjectType.fromString(type);
  }
}
