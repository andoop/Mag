import '../models.dart';

/// 工作区文件引用工具：供时间线与模型输出中的可点击引用对齐。
/// OpenCode 无同名工具，其 `default.txt` 仅约定正文里 `path:line` 写法；此处用结构化工具保证移动端可渲染 chips。
const String kFilerefToolDescription = r'''
Register workspace file paths you created or modified in this turn so the user can tap them in the chat timeline.

## When you MUST call this tool (mandatory)
Immediately after any successful batch of file mutations, call `fileref` **in the same assistant turn**, before you finish your short reply:
- After `write`, `edit`, `apply_patch`, `delete`, `rename`, `move`, or `copy` that changed the workspace.
- Include **every** file path you added or changed in that batch (deduplicate paths).
- Use `kind: "created"` for brand-new files, `kind: "modified"` for updates to existing files.

## Optional prose (in addition to the tool)
You may still mention locations as `path:line` in natural language (OpenCode style), but **do not** skip `fileref` when you touched files.

## Parameters
- `refs`: array of `{ "path": "workspace-relative/path", "kind": "created" | "modified" }`
- Paths must stay under the workspace root, POSIX slashes. `.` / `./` are normalized; `..` is resolved and rejected if it would escape the root.

## When NOT to call
- Read-only steps (`read`, `list`, `glob`, `grep`, `stat`) with no writes.
- Plan mode where edits are blocked (no files changed).
''';

JsonMap filerefToolParametersSchema() => {
      'type': 'object',
      'properties': {
        'refs': {
          'type': 'array',
          'description':
              'Files created or modified in this turn (workspace-relative paths)',
          'items': {
            'type': 'object',
            'properties': {
              'path': {
                'type': 'string',
                'description': 'Workspace-relative file path',
              },
              'kind': {
                'type': 'string',
                'description': 'created | modified',
                'enum': ['created', 'modified'],
              },
            },
            'required': ['path', 'kind'],
            'additionalProperties': false,
          },
          'minItems': 1,
        },
      },
      'required': ['refs'],
      'additionalProperties': false,
    };
