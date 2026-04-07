# Mobile Agent 内置 AI 工具说明

> 文档索引见 [docs/README.md](README.md)。架构背景见 [architecture.md](architecture.md)。

本文档描述 `lib/core/tool_runtime.dart` 中 `ToolRegistry.builtins()` 注册的工具，以及 `lib/core/agents.dart` 中各 Agent 的可见工具与权限差异。

---

## 按 Agent 可见性

| Agent | 模式 | 可用工具 ID |
|--------|------|-------------|
| **build** | 主会话默认 | `read`, `list`, `write`, `edit`, `apply_patch`, `glob`, `grep`, `stat`, `delete`, `rename`, `move`, `copy`, `task`, `todowrite`, `question`, `webfetch`, `browser`, `skill`, `invalid`, `plan_exit` |
| **general** | 子代理 | 与 build 相同（`todowrite` 在权限规则中可能被 deny，见 `agents.dart`） |
| **plan** | 主会话规划 | `read`, `list`, `glob`, `grep`, `stat`, `question`, `webfetch`, `browser`, `skill`, `todowrite`, `task`, `plan_exit`, `invalid`（**无** `write` / `edit` / `apply_patch` 及 `delete` / `rename` / `move` / `copy`） |
| **explore** | 子代理探索 | `read`, `list`, `glob`, `grep`, `stat`, `webfetch`, `browser`, `skill`, `question`, `invalid`（**无** 写类、`task`、`todowrite`、`plan_exit`） |

默认权限规则要点（可被各 Agent 覆盖）：

- `question`：默认 deny；**build** 通过 override 放行。
- `plan_exit`：默认 deny；**plan** 放行。
- `webfetch`：默认 ask（需用户确认）。
- `*.env` / `*.env.*` 的 `read` / `edit`：默认 ask。

---

## 路径规则（文件类工具通用）

路径均为**相对工作区根**，不是设备文件系统的绝对路径（如 `/sdcard/...`）。服务端会统一规范化：

- 使用 `/`，并 trim；反斜杠会转为 `/`。
- 去掉开头的 `/`（仍表示在工作区内的相对路径）。
- 折叠 `.`、空段、以及前导的 `./`（例如 `./lib/main.dart` → `lib/main.dart`）。
- 解析 `..`；若结果会**超出工作区根**（例如 `../outside`），则报错。
- `.` 或空字符串表示工作区根（适用于 `read` 列根目录等）。

模型可放心使用 `lib/foo.dart`、`./lib/foo.dart`、`foo/../bar`（等价于 `bar`）等写法。

---

## 工具一览

### 1. `read`

**作用**：读取工作区内文本文件（带行号），或列出目录条目；**省略 `path`** 时表示工作区根目录列表。

**参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `path` | string | 可选，相对工作区根的路径 |
| `offset` | integer | 可选，从第几行（文件）或第几条（目录）开始，默认 `1` |
| `limit` | integer | 可选，最多行数/条目数，默认 `2000`，上限 `5000` |

**行为要点**：

- 单行最长约 2000 字符，超出会截断并标注。
- 总输出约 **50KB** 上限；超出需用更大 `offset` 续读。
- 图片 / PDF：返回附件元数据，非全文文本。
- 判定为二进制且非上述类型：抛错。

**示例**：

```json
{ "path": "lib/main.dart", "offset": 1, "limit": 100 }
```

```json
{ "path": "lib" }
```

```json
{}
```

---

### 2. `write`

**作用**：新建或覆盖文件。执行前会走 **`edit` 权限**（含 diff 预览）。

**参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `path` | string | **必填**，相对路径 |
| `content` | string | 可选，直接写入的短文本 |
| `contentRef` | string | 可选，对应同条助手消息中 `<write_content id="...">...</write_content>` 的 `id` |

**示例（短内容）**：

```json
{ "path": "docs/note.md", "content": "# Hello" }
```

**示例（大块内容）**：助手正文先输出：

```xml
<write_content id="main-dart">
```dart
void main() {}
```
</write_content>
```

再调用：

```json
{ "path": "lib/main.dart", "contentRef": "main-dart" }
```

---

### 3. `edit`

**作用**：在文件中用 `oldString` 替换为 `newString`。需 **`edit` 权限**。

**参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `path` | string | **必填** |
| `oldString` | string | **必填** |
| `newString` | string | **必填** |
| `replaceAll` | boolean | 可选，默认 `false`（仅替换第一处） |

**示例**：

```json
{
  "path": "lib/foo.dart",
  "oldString": "oldValue",
  "newString": "newValue",
  "replaceAll": false
}
```

---

### 4. `apply_patch`

**作用**：按 Mag 风格补丁批量增删改移动文件。每段变更需 **`edit` 权限**。

**参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `patchText` | string | **必填** |

**补丁段落标记**（与 `tool_runtime.dart` 解析一致）：

- `*** Add File: <path>` — 新增文件，内容行以 `+` 开头。
- `*** Update File: <path>` — 修改；使用 `@@` 开始 hunk，行前缀：` `（上下文）、`-`（删）、`+`（增）。
- `*** Delete File: <path>` — 删除文件。
- `*** Move to: <newpath>` — 与 Update 配合表示移动（先写目标路径行）。

**Update 示例**：

```text
*** Update File: lib/a.dart
@@
- old line
+ new line
```

---

### 5. `list`

**作用**：在工作区下列出文件并渲染为树状文本。默认忽略常见目录（如 `.git/`、`node_modules/`、`build/`、`.dart_tool/` 等，见代码中 `_kDefaultWorkspaceIgnorePatterns`）。

**参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `path` | string | 可选，子目录；空为根 |
| `ignore` | string[] | 可选，额外忽略模式 |

**注意**：结果最多约 **100** 个文件（`_kToolResultLimit`），超出会截断。

**示例**：

```json
{ "path": "lib", "ignore": ["**/*.g.dart"] }
```

---

### 6. `glob`

**作用**：按 glob 模式搜索文件路径。

**参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `pattern` | string | **必填**，如 `**/*.dart` |
| `path` | string | 可选，限定搜索根子路径 |

**示例**：

```json
{ "pattern": "**/test/**/*_test.dart", "path": "packages" }
```

---

### 7. `grep`

**作用**：用正则表达式按**行**搜索文件内容（经 `WorkspaceBridge.grepText` → Android `grepWorkspace`）。正则为 **Kotlin `Regex`**，与 ripgrep/PCRE 不完全相同。

**参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `pattern` | string | **必填**，每行独立匹配 |
| `path` | string | 可选，必须是工作区内的**目录**（不能传单个文件路径；搜单文件请 `read` 或传父目录 + `include`/`glob`） |
| `include` | string | 可选，glob；与 **`glob` 二选一**（`include` 非空时优先） |
| `glob` | string | 可选，**`include` 的别名**，方便与常见工具命名对齐 |

**`include` / `glob` 语义**：按**整条工作区相对路径**匹配（如 `lib/main.dart`），不是仅文件名。子目录下按扩展名过滤请用 `**/*.dart`；仅用 `*.dart` 只会匹配根目录下一层文件名。

**示例**：

```json
{ "pattern": "class\\s+Foo", "path": "lib", "include": "**/*.dart" }
```

在整仓中只搜 Dart：

```json
{ "pattern": "WorkspaceBridge", "glob": "**/*.dart" }
```

---

### 8. `stat`

**作用**：获取文件或目录元数据（不读取文件内容）。对应 `WorkspaceBridge.stat` / `getEntry`。

**参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `path` | string | **必填**，相对工作区根的路径 |

**返回字段**：`path`、`name`、`isDirectory`、`size`、`lastModified`（毫秒时间戳）、`mimeType`（若有）。

**示例**：

```json
{ "path": "lib/main.dart" }
```

---

### 9. `delete`

**作用**：删除文件或目录（目录递归删除）。需 **`edit` 权限**。

**参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `path` | string | **必填** |

**示例**：

```json
{ "path": "tmp/old.txt" }
```

---

### 10. `rename`

**作用**：在同一父目录下重命名（仅改文件名）。需 **`edit` 权限**。若需跨目录路径变更，请用 **`move`**。

**参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `path` | string | **必填**，原相对路径 |
| `newName` | string | **必填**，新文件名（不含 `/`） |

**示例**：

```json
{ "path": "lib/foo.dart", "newName": "bar.dart" }
```

---

### 11. `move`

**作用**：将文件或目录移动到新的工作区相对路径（`toPath` 为最终路径，含文件名）。需 **`edit` 权限**。Android 上优先使用 `DocumentsContract.moveDocument`（API 24+），否则回退为复制后删除源。

**参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `fromPath` | string | **必填**，源路径 |
| `toPath` | string | **必填**，目标路径 |

**示例**：

```json
{ "fromPath": "draft/a.txt", "toPath": "src/a.txt" }
```

---

### 12. `copy`

**作用**：复制文件或目录到另一路径（目录递归复制；平台限制深度与文件数）。需 **`edit` 权限**。

**参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `fromPath` | string | **必填**，源路径 |
| `toPath` | string | **必填**，目标路径 |

**示例**：

```json
{ "fromPath": "lib/a.dart", "toPath": "lib/a_backup.dart" }
```

---

### 13. `todowrite`

**作用**：将待办列表写入当前会话并持久化。

**参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `todos` | array | **必填**；每项至少含 `content`、`status`；可选 `id`、`priority` |

**示例**：

```json
{
  "todos": [
    { "id": "1", "content": "Refactor X", "status": "in_progress", "priority": "high" },
    { "content": "Add tests", "status": "pending" }
  ]
}
```

---

### 14. `question`

**作用**：向用户发起结构化问题，阻塞直到用户作答。结构见 `models.dart` 中 `QuestionInfo`。

**参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `questions` | array | **必填**；每项含 `question`、`header`、`options`（`label` + `description`），可选 `multiple`、`custom` |

**示例**：

```json
{
  "questions": [
    {
      "question": "使用哪种方案？",
      "header": "架构",
      "options": [
        { "label": "A", "description": "方案 A" },
        { "label": "B", "description": "方案 B" }
      ],
      "multiple": false
    }
  ]
}
```

---

### 15. `webfetch`

**作用**：HTTP GET 获取 URL 正文。需 **`webfetch` 权限**（默认多为询问）。

**参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `url` | string | **必填** |

**示例**：

```json
{ "url": "https://example.com/doc" }
```

---

### 16. `browser`

**作用**：在应用内打开工作区内的 **HTML** 页面（返回 `browser_page` 类附件）。

**参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `path` | string | **必填**；可为目录，会尝试 `index.html` / `index.htm` |

**示例**：

```json
{ "path": "web/dist/index.html" }
```

---

### 17. `skill`

**作用**：按名称读取内置短技能说明（注入模型上下文）。

**参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `name` | string | **必填**；当前实现：`android_workspace`、`mobile_agent` |

**示例**：

```json
{ "name": "mobile_agent" }
```

---

### 18. `invalid`

**作用**：由模型或管线声明某次工具调用非法，用于自纠与展示。

**参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `tool` | string | **必填** |
| `error` | string | **必填** |

**示例**：

```json
{ "tool": "write", "error": "missing path" }
```

---

### 19. `plan_exit`

**作用**：在 **plan** 模式下请求切换到 **build**；会弹出确认。用户选择停留则抛错。

**参数**：无（空对象 `{}`）。

---

### 20. `task`

**作用**：创建子会话，使用指定子代理执行 `prompt`，返回最后助手输出（包在 `<task_result>` 中）。

**参数**：

| 参数 | 类型 | 说明 |
|------|------|------|
| `description` | string | **必填**，任务标题 |
| `prompt` | string | **必填**，子会话用户消息 |
| `subagent_type` | string | 可选，默认 `general`；与 `AgentRegistry` 名称一致：`build`、`plan`、`general`、`explore` |

**示例**：

```json
{
  "description": "梳理 lib/core 依赖",
  "prompt": "只读分析 tool_runtime.dart 的依赖关系，简要输出。",
  "subagent_type": "explore"
}
```

---

## 实现与维护

- 工具注册：`lib/core/tool_runtime.dart` → `ToolRegistry.builtins()`。
- Agent 与权限：`lib/core/agents.dart`。
- 工作区桥接：`lib/core/workspace_bridge.dart`；`stat` / `delete` / `rename` / `move` / `copy` 对应 MethodChannel 方法名与 Android 实现见 `android/app/src/main/kotlin/.../MainActivity.kt` 中的 `renameEntry`、`moveEntry`、`copyEntry`（`deleteEntry` 已存在）。**当前仅 Android 侧实现；若在其他平台调用未实现的原生方法会失败。**
- 若修改 `availableTools` 或 `PermissionRule`，请同步更新本文档。
