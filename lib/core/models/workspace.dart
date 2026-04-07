part of '../models.dart';

class WorkspaceInfo {
  WorkspaceInfo({
    required this.id,
    required this.name,
    required this.treeUri,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String treeUri;
  final int createdAt;

  JsonMap toJson() => {
        'id': id,
        'name': name,
        'treeUri': treeUri,
        'createdAt': createdAt,
      };

  factory WorkspaceInfo.fromJson(JsonMap json) => WorkspaceInfo(
        id: json['id'] as String,
        name: json['name'] as String,
        treeUri: json['treeUri'] as String,
        createdAt: json['createdAt'] as int,
      );
}

class ProjectInfo {
  ProjectInfo({
    required this.id,
    required this.workspaceId,
    required this.name,
    required this.createdAt,
  });

  final String id;
  final String workspaceId;
  final String name;
  final int createdAt;

  JsonMap toJson() => {
        'id': id,
        'workspaceId': workspaceId,
        'name': name,
        'createdAt': createdAt,
      };

  factory ProjectInfo.fromJson(JsonMap json) => ProjectInfo(
        id: json['id'] as String,
        workspaceId: json['workspaceId'] as String,
        name: json['name'] as String,
        createdAt: json['createdAt'] as int,
      );
}

class WorkspaceEntry {
  WorkspaceEntry({
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.lastModified,
    required this.size,
    this.mimeType,
  });

  final String path;
  final String name;
  final bool isDirectory;
  final int lastModified;
  final int size;
  final String? mimeType;

  JsonMap toJson() => {
        'path': path,
        'name': name,
        'isDirectory': isDirectory,
        'lastModified': lastModified,
        'size': size,
        'mimeType': mimeType,
      };

  factory WorkspaceEntry.fromJson(JsonMap json) => WorkspaceEntry(
        path: json['path'] as String,
        name: json['name'] as String,
        isDirectory: json['isDirectory'] as bool,
        lastModified: (json['lastModified'] as int?) ?? 0,
        size: (json['size'] as int?) ?? 0,
        mimeType: json['mimeType'] as String?,
      );
}

class WorkspaceSearchEntry {
  WorkspaceSearchEntry({
    required this.path,
    required this.content,
  });

  final String path;
  final String content;

  JsonMap toJson() => {
        'path': path,
        'content': content,
      };

  factory WorkspaceSearchEntry.fromJson(JsonMap json) => WorkspaceSearchEntry(
        path: json['path'] as String,
        content: json['content'] as String,
      );
}
