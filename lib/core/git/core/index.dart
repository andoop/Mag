/// Git index (staging area) handler
library;

import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../exceptions/git_exceptions.dart';

/// Index entry representing a staged file
class IndexEntry {
  final int ctimeSeconds;
  final int ctimeNanoseconds;
  final int mtimeSeconds;
  final int mtimeNanoseconds;
  final int dev;
  final int ino;
  final int mode;
  final int uid;
  final int gid;
  final int fileSize;
  final String hash;
  final int flags;
  final String path;

  const IndexEntry({
    required this.ctimeSeconds,
    required this.ctimeNanoseconds,
    required this.mtimeSeconds,
    required this.mtimeNanoseconds,
    required this.dev,
    required this.ino,
    required this.mode,
    required this.uid,
    required this.gid,
    required this.fileSize,
    required this.hash,
    required this.flags,
    required this.path,
  });

  /// Create index entry from file
  static Future<IndexEntry> fromFile(
      String path, String hash, FileStat stat) async {
    final nameLength = path.length < 0xFFF ? path.length : 0xFFF;
    final flags = nameLength & 0xFFF; // 12 bits for name length

    return IndexEntry(
      ctimeSeconds: stat.changed.millisecondsSinceEpoch ~/ 1000,
      ctimeNanoseconds: (stat.changed.millisecondsSinceEpoch % 1000) * 1000000,
      mtimeSeconds: stat.modified.millisecondsSinceEpoch ~/ 1000,
      mtimeNanoseconds: (stat.modified.millisecondsSinceEpoch % 1000) * 1000000,
      dev: 0, // Not used on all platforms
      ino: 0, // Not used on all platforms
      mode: _getMode(stat),
      uid: 0,
      gid: 0,
      fileSize: stat.size,
      hash: hash,
      flags: flags,
      path: path,
    );
  }

  /// Get git mode from file stat
  static int _getMode(FileStat stat) {
    // Git mode format: object type (4 bits) + unix permissions (12 bits)
    // Regular file: 0b1000 (0x8) in bits 12-15
    // Permissions: 0644 (octal) = 0x1A4

    const regularFile = 0x8000; // 0b1000 << 12
    const permissions = 0x1A4; // 0644 octal

    return regularFile | permissions;
  }

  /// Get stage number (0 = normal, 1-3 = merge conflict)
  int get stage => (flags >> 12) & 0x3;

  /// Compare for sorting (by path)
  int compareTo(IndexEntry other) {
    return path.compareTo(other.path);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is IndexEntry &&
        other.path == path &&
        other.hash == hash &&
        other.stage == stage;
  }

  @override
  int get hashCode => Object.hash(path, hash, stage);

  @override
  String toString() => '$path ($hash)';
}

/// Git index file handler
class Index {
  final String indexPath;

  Index(this.indexPath);

  /// Read index entries from file
  Future<List<IndexEntry>> read() async {
    final file = File(indexPath);
    if (!await file.exists()) {
      return [];
    }

    try {
      final data = await file.readAsBytes();
      return _parse(data);
    } catch (e) {
      throw InvalidIndexException('Failed to parse index: $e');
    }
  }

  /// Parse index data
  List<IndexEntry> _parse(Uint8List data) {
    if (data.length < 12) {
      throw const InvalidIndexException('Index too short');
    }

    // Read header
    final signature = String.fromCharCodes(data.sublist(0, 4));
    if (signature != 'DIRC') {
      throw InvalidIndexException('Invalid signature: $signature');
    }

    final version = _readUint32(data, 4);
    if (version < 2 || version > 4) {
      throw InvalidIndexException('Unsupported version: $version');
    }

    final entryCount = _readUint32(data, 8);
    final entries = <IndexEntry>[];

    var offset = 12;
    for (var i = 0; i < entryCount; i++) {
      final entry = _parseEntry(data, offset);
      entries.add(entry[0] as IndexEntry);
      offset = entry[1] as int;
    }

    return entries;
  }

  /// Parse a single index entry. Returns [entry, nextOffset].
  List<dynamic> _parseEntry(Uint8List data, int offset) {
    if (offset + 62 > data.length) {
      throw const InvalidIndexException('Entry truncated');
    }

    final ctimeSeconds = _readUint32(data, offset);
    final ctimeNanoseconds = _readUint32(data, offset + 4);
    final mtimeSeconds = _readUint32(data, offset + 8);
    final mtimeNanoseconds = _readUint32(data, offset + 12);
    final dev = _readUint32(data, offset + 16);
    final ino = _readUint32(data, offset + 20);
    final mode = _readUint32(data, offset + 24);
    final uid = _readUint32(data, offset + 28);
    final gid = _readUint32(data, offset + 32);
    final fileSize = _readUint32(data, offset + 36);

    // Read 20-byte SHA-1
    final hashBytes = data.sublist(offset + 40, offset + 60);
    final hash =
        hashBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    final flags = _readUint16(data, offset + 60);

    // Read path (null-terminated)
    var pathEnd = offset + 62;
    while (pathEnd < data.length && data[pathEnd] != 0) {
      pathEnd++;
    }

    if (pathEnd >= data.length) {
      throw const InvalidIndexException('Path not null-terminated');
    }

    final path = String.fromCharCodes(data.sublist(offset + 62, pathEnd));

    // Calculate padding to align to 8-byte boundary
    final entrySize = 62 + path.length + 1; // +1 for null terminator
    final padding = (8 - (entrySize % 8)) % 8;
    final nextOffset = offset + entrySize + padding;

    final entry = IndexEntry(
      ctimeSeconds: ctimeSeconds,
      ctimeNanoseconds: ctimeNanoseconds,
      mtimeSeconds: mtimeSeconds,
      mtimeNanoseconds: mtimeNanoseconds,
      dev: dev,
      ino: ino,
      mode: mode,
      uid: uid,
      gid: gid,
      fileSize: fileSize,
      hash: hash,
      flags: flags,
      path: path,
    );

    return [entry, nextOffset];
  }

  /// Write index entries to file
  Future<void> write(List<IndexEntry> entries) async {
    // Sort entries by path
    final sorted = List<IndexEntry>.from(entries)
      ..sort((a, b) => a.compareTo(b));

    final data = _serialize(sorted);

    final file = File(indexPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data);
  }

  /// Serialize index to bytes
  Uint8List _serialize(List<IndexEntry> entries) {
    final builder = BytesBuilder();

    // Write header
    builder.add('DIRC'.codeUnits);
    _writeUint32(builder, 2); // Version 2
    _writeUint32(builder, entries.length);

    // Write entries
    for (final entry in entries) {
      _writeEntry(builder, entry);
    }

    // Calculate and write checksum
    final content = builder.toBytes();
    final checksum = sha1.convert(content);
    builder.add(checksum.bytes);

    return builder.toBytes();
  }

  /// Write a single entry
  void _writeEntry(BytesBuilder builder, IndexEntry entry) {
    _writeUint32(builder, entry.ctimeSeconds);
    _writeUint32(builder, entry.ctimeNanoseconds);
    _writeUint32(builder, entry.mtimeSeconds);
    _writeUint32(builder, entry.mtimeNanoseconds);
    _writeUint32(builder, entry.dev);
    _writeUint32(builder, entry.ino);
    _writeUint32(builder, entry.mode);
    _writeUint32(builder, entry.uid);
    _writeUint32(builder, entry.gid);
    _writeUint32(builder, entry.fileSize);

    // Write SHA-1 (20 bytes)
    final hashBytes = _hexToBytes(entry.hash);
    builder.add(hashBytes);

    _writeUint16(builder, entry.flags);

    // Write path with null terminator
    builder.add(entry.path.codeUnits);
    builder.addByte(0);

    // Add padding to align to 8-byte boundary
    final entrySize = 62 + entry.path.length + 1;
    final padding = (8 - (entrySize % 8)) % 8;
    for (var i = 0; i < padding; i++) {
      builder.addByte(0);
    }
  }

  /// Read 32-bit unsigned integer (big-endian)
  int _readUint32(Uint8List data, int offset) {
    return (data[offset] << 24) |
        (data[offset + 1] << 16) |
        (data[offset + 2] << 8) |
        data[offset + 3];
  }

  /// Read 16-bit unsigned integer (big-endian)
  int _readUint16(Uint8List data, int offset) {
    return (data[offset] << 8) | data[offset + 1];
  }

  /// Write 32-bit unsigned integer (big-endian)
  void _writeUint32(BytesBuilder builder, int value) {
    builder.addByte((value >> 24) & 0xFF);
    builder.addByte((value >> 16) & 0xFF);
    builder.addByte((value >> 8) & 0xFF);
    builder.addByte(value & 0xFF);
  }

  /// Write 16-bit unsigned integer (big-endian)
  void _writeUint16(BytesBuilder builder, int value) {
    builder.addByte((value >> 8) & 0xFF);
    builder.addByte(value & 0xFF);
  }

  /// Convert hex string to bytes
  Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return result;
  }

  /// Add or update an entry
  Future<void> addEntry(IndexEntry entry) async {
    final entries = await read();

    // Remove existing entry with same path
    entries.removeWhere((e) => e.path == entry.path);

    // Add new entry
    entries.add(entry);

    await write(entries);
  }

  /// Remove an entry
  Future<void> removeEntry(String path) async {
    final entries = await read();
    entries.removeWhere((e) => e.path == path);
    await write(entries);
  }

  /// Get entry by path
  Future<IndexEntry?> getEntry(String path) async {
    final entries = await read();
    final matches = entries.where((e) => e.path == path);
    return matches.isEmpty ? null : matches.first;
  }

  /// Clear all entries
  Future<void> clear() async {
    await write([]);
  }
}
