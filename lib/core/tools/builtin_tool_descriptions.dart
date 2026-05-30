/// Compact tool descriptions optimized for mobile payload size.

const String kReadToolDescription = r'''
Read a workspace file or directory.
- Required: `filePath`.
- Files return numbered lines; do not copy the line-number prefix into edits.
- Use `offset`/`limit` for large files. Use `grep`/`glob` when locating content.
- Images and PDFs may be returned as attachments.
''';

const String kWriteToolDescription = r'''
Create or overwrite a workspace file.
- Required: `filePath`, `content`.
- Existing files require a fresh `read` first.
- Prefer edit-style tools for modifying existing files.
- On success the result returns the applied diff: that IS the file's current
  state. Do not re-read or reuse an earlier `read` to reason about it.
''';

const String kEditToolDescription = r'''
Replace exact text in an existing workspace file.
- Read the file first and copy exact content without line-number prefixes.
- `oldString` must match uniquely unless `replaceAll` is true.
- If matching fails, read again and use a larger exact block.
- On success the result returns the applied diff: that IS the file's current
  state. Do not re-read or reuse an earlier `read` to reason about it.
''';

const String kApplyPatchToolDescription = r'''
Edit workspace files with a patch envelope:

*** Begin Patch
[ one or more file sections ]
*** End Patch

Sections:
- `*** Add File: <path>` then `+` lines.
- `*** Update File: <path>` with diff hunks; optional `*** Move to: <path>`.
- `*** Delete File: <path>`.

Example patch:

```
*** Begin Patch
*** Add File: hello.txt
+Hello world
*** Update File: src/app.py
*** Move to: src/main.py
@@ def greet():
-print("Hi")
+print("Hello, world!")
*** Delete File: obsolete.txt
*** End Patch
```

It is important to remember:
- Existing files must be read first.
- New lines in added files must start with `+`.
''';

const String kWebfetchToolDescription = r'''
Fetch public web text for inspection. Read-only; does not save files.
- Required: `url`.
- Use `download` instead when the remote file must be saved to the workspace.
''';

const String kDownloadToolDescription = r'''
Download a public file from a URL into the workspace.
- Required: `url`, `filePath`.
- URL must be public `http`/`https`.
- Existing destination requires `overwrite: true`.
''';

const String kListMcpResourcesToolDescription = r'''
List resources from configured MCP servers. Optional `serverId` narrows results.
''';

const String kReadMcpResourceToolDescription = r'''
Read an MCP resource. Required: `serverId`, `uri`. Use `list_mcp_resources` to discover URIs.
''';

const String kListMcpPromptsToolDescription = r'''
List prompt templates from configured MCP servers. Optional `serverId` narrows results.
''';

const String kGetMcpPromptToolDescription = r'''
Resolve an MCP prompt. Required: `serverId`, `name`; optional `arguments`.
''';

/// Client-specific: workspace-relative paths.
const String kMobileWorkspacePathSuffix = '''

Paths are workspace-relative, use `/`, and cannot escape the workspace.''';

/// Client-specific: fetch returns plain text; format/timeout options are not exposed.
const String kMobileWebFetchSuffix = '''

Returns plain text only; no `format` or `timeout` parameters.''';
