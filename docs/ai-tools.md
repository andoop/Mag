# AI Tools

Mag exposes tools to agents so they can work inside a mobile workspace. Tools are permission-aware, workspace-relative, and visible to the user.

## Tool Categories

| Category | Tools |
|----------|-------|
| File read/write | `read`, `list`, `stat`, `write`, `edit`, `apply_patch` |
| Search | `glob`, `grep` |
| File operations | `delete`, `rename`, `move`, `copy` |
| Git | `git` |
| Work tracking | `task`, `todowrite`, `question` |
| Variables | `variable` |
| Network | `webfetch`, `download` |
| Generated artifacts | `create_document`, `create_spreadsheet`, `create_presentation`, `create_qr_code` |
| MCP | `list_mcp_resources`, `read_mcp_resource`, `list_mcp_prompts`, `get_mcp_prompt` |
| Skills | `skill` |
| Runtime | `browser`, `plan_exit`, `invalid` |

## Agent Visibility

| Agent | Purpose | Tool Shape |
|-------|---------|------------|
| `build` | Default coding agent | Full tool surface with write/edit and user-facing questions. |
| `plan` | Planning | Read/search/question-oriented tools; destructive write operations are not exposed. |
| `explore` | Read-only exploration | Read/list/search/resource tools for understanding code. |
| `general` | Sub-agent | Similar to build, with permission differences where configured. |

## Path Rules

- Paths are relative to the workspace root.
- Absolute device paths are not accepted as normal tool paths.
- `.` means the workspace root.
- `..` is normalized and cannot escape the workspace.
- Tools should prefer explicit paths such as `lib/main.dart` or `docs/notes.md`.

## Permissions

Sensitive actions can require approval:

- File edits and generated files.
- Downloads and web access.
- Environment files such as `.env`.
- Destructive file operations.
- Git operations that change working state.

## Generated Artifacts

Office tools create files and return attachments:

- `create_document` -> `.docx`
- `create_spreadsheet` -> `.xlsx`
- `create_presentation` -> `.pptx`
- `create_qr_code` -> `.svg`

See [Document Generation](document-generation.md).

## MCP And Skills

MCP tools let the agent read remote resources and resolve prompt templates. Skills add reusable instructions and references to the conversation; loading a Skill does not secretly run scripts.

---

# AI 工具

Mag 的工具都围绕工作区设计：路径相对工作区根目录，敏感操作走权限确认，工具调用会展示给用户。

重点工具：

- 文件：读、写、编辑、补丁、移动、复制、删除、重命名。
- 搜索：glob、grep。
- Git：状态、diff、提交、分支、同步等聚合能力。
- 生成：DOCX、XLSX、PPTX、二维码 SVG。
- 网络：网页获取、下载。
- 扩展：MCP、Skills。
