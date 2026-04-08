import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'models.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  Future<Database> get database async {
    final existing = _db;
    if (existing != null) return existing;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'mobile_agent.db');
    _db = await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE workspaces (
            id TEXT PRIMARY KEY,
            data TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE projects (
            id TEXT PRIMARY KEY,
            workspace_id TEXT NOT NULL,
            data TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE sessions (
            id TEXT PRIMARY KEY,
            workspace_id TEXT NOT NULL,
            project_id TEXT NOT NULL,
            updated_at INTEGER NOT NULL,
            data TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE messages (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            data TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE parts (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            message_id TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            data TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE tool_permissions (
            id TEXT PRIMARY KEY,
            workspace_id TEXT NOT NULL,
            permission TEXT NOT NULL,
            pattern TEXT NOT NULL,
            action TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE permission_requests (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            data TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE question_requests (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            data TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE todos (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            data TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE workspace_index (
            workspace_id TEXT NOT NULL,
            path TEXT NOT NULL,
            data TEXT NOT NULL,
            PRIMARY KEY (workspace_id, path)
          )
        ''');
        await db.execute('''
          CREATE TABLE workspace_search_index (
            workspace_id TEXT NOT NULL,
            path TEXT NOT NULL,
            data TEXT NOT NULL,
            PRIMARY KEY (workspace_id, path)
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS workspace_search_index (
              workspace_id TEXT NOT NULL,
              path TEXT NOT NULL,
              data TEXT NOT NULL,
              PRIMARY KEY (workspace_id, path)
            )
          ''');
        }
      },
    );
    return _db!;
  }

  Future<void> saveWorkspace(WorkspaceInfo workspace) async {
    final db = await database;
    await db.insert(
      'workspaces',
      {'id': workspace.id, 'data': jsonEncode(workspace.toJson())},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<WorkspaceInfo>> listWorkspaces() async {
    final db = await database;
    final rows = await db.query('workspaces');
    return rows
        .map((row) => WorkspaceInfo.fromJson(jsonDecode(row['data'] as String) as JsonMap))
        .toList();
  }

  Future<void> deleteWorkspaceCascade(String workspaceId) async {
    final db = await database;
    await db.transaction((txn) async {
      final sessionRows = await txn.query(
        'sessions',
        columns: ['id'],
        where: 'workspace_id = ?',
        whereArgs: [workspaceId],
      );
      final sessionIds = sessionRows
          .map((row) => row['id'] as String?)
          .whereType<String>()
          .toList();
      for (final sessionId in sessionIds) {
        await txn.delete('parts', where: 'session_id = ?', whereArgs: [sessionId]);
        await txn.delete('messages', where: 'session_id = ?', whereArgs: [sessionId]);
        await txn.delete(
          'permission_requests',
          where: 'session_id = ?',
          whereArgs: [sessionId],
        );
        await txn.delete(
          'question_requests',
          where: 'session_id = ?',
          whereArgs: [sessionId],
        );
        await txn.delete('todos', where: 'session_id = ?', whereArgs: [sessionId]);
      }
      await txn.delete('sessions', where: 'workspace_id = ?', whereArgs: [workspaceId]);
      await txn.delete('projects', where: 'workspace_id = ?', whereArgs: [workspaceId]);
      await txn.delete(
        'tool_permissions',
        where: 'workspace_id = ?',
        whereArgs: [workspaceId],
      );
      await txn.delete(
        'workspace_index',
        where: 'workspace_id = ?',
        whereArgs: [workspaceId],
      );
      await txn.delete(
        'workspace_search_index',
        where: 'workspace_id = ?',
        whereArgs: [workspaceId],
      );
      await txn.delete('workspaces', where: 'id = ?', whereArgs: [workspaceId]);
    });
  }

  Future<void> migrateWorkspace(
    WorkspaceInfo previous,
    WorkspaceInfo next,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('workspaces', where: 'id = ?', whereArgs: [previous.id]);
      await txn.insert(
        'workspaces',
        {'id': next.id, 'data': jsonEncode(next.toJson())},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      final projectRows = await txn.query(
        'projects',
        where: 'workspace_id = ?',
        whereArgs: [previous.id],
      );
      for (final row in projectRows) {
        final project = ProjectInfo.fromJson(
          jsonDecode(row['data'] as String) as JsonMap,
        );
        final updated = ProjectInfo(
          id: project.id,
          workspaceId: next.id,
          name: project.name,
          createdAt: project.createdAt,
        );
        await txn.update(
          'projects',
          {
            'workspace_id': next.id,
            'data': jsonEncode(updated.toJson()),
          },
          where: 'id = ?',
          whereArgs: [project.id],
        );
      }

      final sessionRows = await txn.query(
        'sessions',
        where: 'workspace_id = ?',
        whereArgs: [previous.id],
      );
      for (final row in sessionRows) {
        final session = SessionInfo.fromJson(
          jsonDecode(row['data'] as String) as JsonMap,
        );
        final updated = SessionInfo(
          id: session.id,
          projectId: session.projectId,
          workspaceId: next.id,
          title: session.title,
          agent: session.agent,
          createdAt: session.createdAt,
          updatedAt: session.updatedAt,
          promptTokens: session.promptTokens,
          completionTokens: session.completionTokens,
          cost: session.cost,
          summaryMessageId: session.summaryMessageId,
        );
        await txn.update(
          'sessions',
          {
            'workspace_id': next.id,
            'data': jsonEncode(updated.toJson()),
          },
          where: 'id = ?',
          whereArgs: [session.id],
        );
      }

      await txn.update(
        'tool_permissions',
        {'workspace_id': next.id},
        where: 'workspace_id = ?',
        whereArgs: [previous.id],
      );
      await txn.update(
        'workspace_index',
        {'workspace_id': next.id},
        where: 'workspace_id = ?',
        whereArgs: [previous.id],
      );
      await txn.update(
        'workspace_search_index',
        {'workspace_id': next.id},
        where: 'workspace_id = ?',
        whereArgs: [previous.id],
      );
    });
  }

  Future<void> saveProject(ProjectInfo project) async {
    final db = await database;
    await db.insert(
      'projects',
      {
        'id': project.id,
        'workspace_id': project.workspaceId,
        'data': jsonEncode(project.toJson()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<ProjectInfo?> projectForWorkspace(String workspaceId) async {
    final db = await database;
    final rows = await db.query(
      'projects',
      where: 'workspace_id = ?',
      whereArgs: [workspaceId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ProjectInfo.fromJson(jsonDecode(rows.first['data'] as String) as JsonMap);
  }

  Future<void> saveSession(SessionInfo session) async {
    final db = await database;
    await db.insert(
      'sessions',
      {
        'id': session.id,
        'workspace_id': session.workspaceId,
        'project_id': session.projectId,
        'updated_at': session.updatedAt,
        'data': jsonEncode(session.toJson()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<SessionInfo>> listSessions(String workspaceId) async {
    final db = await database;
    final rows = await db.query(
      'sessions',
      where: 'workspace_id = ?',
      whereArgs: [workspaceId],
      orderBy: 'updated_at DESC',
    );
    return rows
        .map((row) => SessionInfo.fromJson(jsonDecode(row['data'] as String) as JsonMap))
        .toList();
  }

  Future<SessionInfo?> getSession(String sessionId) async {
    final db = await database;
    final rows = await db.query('sessions', where: 'id = ?', whereArgs: [sessionId], limit: 1);
    if (rows.isEmpty) return null;
    return SessionInfo.fromJson(jsonDecode(rows.first['data'] as String) as JsonMap);
  }

  /// 与 OpenCode `Session.remove` 一致：删除会话及其消息、分片、待办与待处理问答/权限。
  Future<void> deleteSessionCascade(String sessionId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('parts', where: 'session_id = ?', whereArgs: [sessionId]);
      await txn.delete('messages', where: 'session_id = ?', whereArgs: [sessionId]);
      await txn.delete('permission_requests', where: 'session_id = ?', whereArgs: [sessionId]);
      await txn.delete('question_requests', where: 'session_id = ?', whereArgs: [sessionId]);
      await txn.delete('todos', where: 'session_id = ?', whereArgs: [sessionId]);
      await txn.delete('sessions', where: 'id = ?', whereArgs: [sessionId]);
    });
  }

  Future<void> saveMessage(MessageInfo message) async {
    final db = await database;
    await db.insert(
      'messages',
      {
        'id': message.id,
        'session_id': message.sessionId,
        'created_at': message.createdAt,
        'data': jsonEncode(message.toJson()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<MessageInfo>> listMessages(String sessionId) async {
    final db = await database;
    final rows = await db.query(
      'messages',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'created_at ASC',
    );
    return rows
        .map((row) => MessageInfo.fromJson(jsonDecode(row['data'] as String) as JsonMap))
        .toList();
  }

  Future<void> savePart(MessagePart part) async {
    final db = await database;
    await db.insert(
      'parts',
      {
        'id': part.id,
        'session_id': part.sessionId,
        'message_id': part.messageId,
        'created_at': part.createdAt,
        'data': jsonEncode(part.toJson()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<MessagePart>> listPartsForMessage(String messageId) async {
    final db = await database;
    final rows = await db.query(
      'parts',
      where: 'message_id = ?',
      whereArgs: [messageId],
      orderBy: 'created_at ASC',
    );
    return rows
        .map((row) => MessagePart.fromJson(jsonDecode(row['data'] as String) as JsonMap))
        .toList();
  }

  Future<List<MessagePart>> listPartsForSession(String sessionId) async {
    final db = await database;
    final rows = await db.query(
      'parts',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'created_at ASC',
    );
    return rows
        .map((row) => MessagePart.fromJson(jsonDecode(row['data'] as String) as JsonMap))
        .toList();
  }

  Future<void> saveToolPermission(String workspaceId, PermissionRule rule) async {
    final db = await database;
    await db.insert(
      'tool_permissions',
      {
        'id': newId('rule'),
        'workspace_id': workspaceId,
        'permission': rule.permission,
        'pattern': rule.pattern,
        'action': rule.action.name,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<PermissionRule>> listToolPermissions(String workspaceId) async {
    final db = await database;
    final rows = await db.query(
      'tool_permissions',
      where: 'workspace_id = ?',
      whereArgs: [workspaceId],
    );
    return rows
        .map(
          (row) => PermissionRule(
            permission: row['permission'] as String,
            pattern: row['pattern'] as String,
            action: PermissionAction.values.firstWhere((item) => item.name == row['action']),
          ),
        )
        .toList();
  }

  Future<void> savePermissionRequest(PermissionRequest request) async {
    final db = await database;
    await db.insert(
      'permission_requests',
      {
        'id': request.id,
        'session_id': request.sessionId,
        'data': jsonEncode(request.toJson()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deletePermissionRequest(String requestId) async {
    final db = await database;
    await db.delete('permission_requests', where: 'id = ?', whereArgs: [requestId]);
  }

  Future<List<PermissionRequest>> listPermissionRequests() async {
    final db = await database;
    final rows = await db.query('permission_requests');
    return rows
        .map((row) => PermissionRequest.fromJson(jsonDecode(row['data'] as String) as JsonMap))
        .toList();
  }

  Future<void> saveQuestionRequest(QuestionRequest request) async {
    final db = await database;
    await db.insert(
      'question_requests',
      {
        'id': request.id,
        'session_id': request.sessionId,
        'data': jsonEncode(request.toJson()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteQuestionRequest(String requestId) async {
    final db = await database;
    await db.delete('question_requests', where: 'id = ?', whereArgs: [requestId]);
  }

  Future<List<QuestionRequest>> listQuestionRequests() async {
    final db = await database;
    final rows = await db.query('question_requests');
    return rows
        .map((row) => QuestionRequest.fromJson(jsonDecode(row['data'] as String) as JsonMap))
        .toList();
  }

  Future<void> saveTodo(TodoItem todo) async {
    final db = await database;
    await db.insert(
      'todos',
      {
        'id': todo.id,
        'session_id': todo.sessionId,
        'data': jsonEncode(todo.toJson()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 与 OpenCode `Todo.update` 一致：写入前先清空本会话全部待办，再插入新列表。
  Future<void> deleteTodosForSession(String sessionId) async {
    final db = await database;
    await db.delete('todos', where: 'session_id = ?', whereArgs: [sessionId]);
  }

  Future<List<TodoItem>> listTodos(String sessionId) async {
    final db = await database;
    final rows = await db.query('todos', where: 'session_id = ?', whereArgs: [sessionId]);
    final list = rows
        .map((row) => TodoItem.fromJson(jsonDecode(row['data'] as String) as JsonMap))
        .toList();
    list.sort((a, b) => a.position.compareTo(b.position));
    return list;
  }

  Future<void> putSetting(String key, JsonMap value) async {
    final db = await database;
    await db.insert(
      'settings',
      {'key': key, 'value': jsonEncode(value)},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<JsonMap?> getSetting(String key) async {
    final db = await database;
    final rows = await db.query('settings', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return jsonDecode(rows.first['value'] as String) as JsonMap;
  }

  Future<void> replaceWorkspaceIndex(String workspaceId, List<WorkspaceEntry> entries) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('workspace_index', where: 'workspace_id = ?', whereArgs: [workspaceId]);
      final batch = txn.batch();
      for (final entry in entries) {
        batch.insert('workspace_index', {
          'workspace_id': workspaceId,
          'path': entry.path,
          'data': jsonEncode(entry.toJson()),
        });
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<WorkspaceEntry>> listWorkspaceIndex(String workspaceId) async {
    final db = await database;
    final rows = await db.query(
      'workspace_index',
      where: 'workspace_id = ?',
      whereArgs: [workspaceId],
    );
    return rows
        .map((row) => WorkspaceEntry.fromJson(jsonDecode(row['data'] as String) as JsonMap))
        .toList();
  }

  Future<void> replaceWorkspaceSearchIndex(
    String workspaceId,
    List<WorkspaceSearchEntry> entries,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('workspace_search_index', where: 'workspace_id = ?', whereArgs: [workspaceId]);
      final batch = txn.batch();
      for (final entry in entries) {
        batch.insert('workspace_search_index', {
          'workspace_id': workspaceId,
          'path': entry.path,
          'data': jsonEncode(entry.toJson()),
        });
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<WorkspaceSearchEntry>> listWorkspaceSearchIndex(String workspaceId) async {
    final db = await database;
    final rows = await db.query(
      'workspace_search_index',
      where: 'workspace_id = ?',
      whereArgs: [workspaceId],
    );
    return rows
        .map((row) => WorkspaceSearchEntry.fromJson(jsonDecode(row['data'] as String) as JsonMap))
        .toList();
  }
}
