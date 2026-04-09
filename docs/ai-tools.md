# Mobile Agent 内置 AI 工具说明

> 文档索引见 [docs/README.md](README.md)。架构背景见 [architecture.md](architecture.md)。

本文档描述 `lib/core/tool_runtime.dart` 中 `ToolRegistry.builtins()` 注册的工具，以及 `lib/core/agents.dart` 中各 Agent 的可见工具与权限差异。

---

## 按 Agent 可见性


| Agent       | 模式    | 可用工具 ID                                                                                                                                                                                                         |
| ----------- | ----- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **build**   | 主会话默认 | `read`, `list`, `write`, `edit`, `apply_patch`, `glob`, `grep`, `stat`, `delete`, `rename`, `move`, `copy`, `task`, `todowrite`, `question`, `webfetch`, `browser`, `skill`, `invalid`, `plan_exit`             |
| **general** | 子代理   | 与 build 相同（`todowrite` 在权限规则中可能被 deny，见 `agents.dart`）                                                                                                                                                          |
| **plan**    | 主会话规划 | `read`, `list`, `glob`, `grep`, `stat`, `question`, `webfetch`, `browser`, `skill`, `todowrite`, `task`, `plan_exit`, `invalid`（**无** `write` / `edit` / `apply_patch` 及 `delete` / `rename` / `move` / `copy`） |
| **explore** | 子代理探索 | `read`, `list`, `glob`, `grep`, `stat`, `webfetch`, `browser`, `skill`, `question`, `invalid`（**无** 写类、`task`、`todowrite`、`plan_exit`）                                                                          |


默认权限规则要点（可被各 Agent 覆盖）：

- `question`：默认 deny；**build** 通过 override 放行。
- `plan_exit`：默认 deny；**plan** 放行。
- `webfetch`：默认 ask（需用户确认）。
- `*.env` / `*.env.*` 的 `read` / `edit`：默认 ask。

写类工具的实际暴露还会按模型做一次路由：

- GPT 系列（排除 `gpt-4*` 与 `*oss*`）优先暴露 `apply_patch`，隐藏 `write` / `edit`。
- 其他模型优先暴露 `write` / `edit`，隐藏 `apply_patch`。

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

**作用**：读取工作区内文本文件（带 `LINE#ID` 哈希锚点），或列出目录条目；**省略 `path`** 时表示工作区根目录列表。

**参数**：


| 参数       | 类型      | 说明                              |
| -------- | ------- | ------------------------------- |
| `path`   | string  | 可选，相对工作区根的路径                    |
| `offset` | integer | 可选，从第几行（文件）或第几条（目录）开始，默认 `1`    |
| `limit`  | integer | 可选，最多行数/条目数，默认 `2000`，上限 `5000` |


**行为要点**：

- 单行最长约 2000 字符，超出会截断并标注。
- 未截断的文本行会以 `LINE#ID|内容` 形式返回，例如 `12#VK|final answer = 42;`。
- 截断行仍保留普通行号展示，此类行不要直接拿去做 hashline 锚点编辑。
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

**作用**：新建或覆盖文件。执行前会走 `**edit` 权限**（含 diff 预览）。

**参数**：


| 参数           | 类型     | 说明                                                                |
| ------------ | ------ | ----------------------------------------------------------------- |
| `path`       | string | **必填**，相对路径                                                       |
| `content`    | string | 可选，直接写入的短文本                                                       |
| `contentRef` | string | 可选，对应同条助手消息中 `<write_content id="...">...</write_content>` 的 `id` |


**行为要点**：

- 若目标文件已存在，必须先用 `read` 读取；否则工具会直接失败。
- 若上次 `read` 之后文件又被外部修改，工具也会拒绝写入，要求重新 `read` 最新内容。
- `content` 与 `contentRef` 二选一即可；大段内容更推荐 `contentRef`。
- 成功写入后，会把该文件的最新时间戳回写到会话 ledger，供后续 `edit` / `apply_patch` 继续使用。

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

```

再调用：

```json
{ "path": "lib/main.dart", "contentRef": "main-dart" }
```

---

### 3. `edit`

**作用**：优先使用基于内容哈希的 `LINE#ID` 锚点编辑文件；兼容旧的 `oldString` / `newString` 文本替换。需 `**edit` 权限**。

**参数**：


| 参数 | 类型 | 说明 |
| --- | --- | --- |
| `path` / `filePath` | string | 目标文件，相对路径 |
| `edits` | array | hashline 编辑操作数组，推荐用法 |
| `delete` | boolean | 可选，删除文件 |
| `rename` | string | 可选，编辑后另存/移动到新路径 |
| `oldString` | string | 兼容旧接口时使用 |
| `newString` | string | 兼容旧接口时使用 |
| `replaceAll` | boolean | 兼容旧接口时使用 |


**行为要点**：

- 必须先 `read` 目标文件，并直接复用返回的 `LINE#ID` 锚点。
- `edits` 中每项只支持 `replace` / `append` / `prepend` 三种操作。
- `replace` 的 `lines: null` 等价于删除目标行或目标区间。
- 如果文件在读取后发生变化，锚点校验会失败，并返回带 `>>>` 标记的最新可用锚点片段。
- 若刚成功改过同一文件、还要继续改，建议先重新 `read` 最新内容，再生成新的锚点。
- 成功写回后也会刷新会话内的 read ledger。

**示例**：

```json
{
  "path": "lib/foo.dart",
  "edits": [
    {
      "op": "replace",
      "pos": "12#VK",
      "lines": ["final value = 42;"]
    }
  ]
}
```

---

### 4. `apply_patch`

**作用**：按 Mag 风格补丁批量增删改移动文件。每段变更需 `**edit` 权限**。

**参数**：


| 参数          | 类型     | 说明     |
| ----------- | ------ | ------ |
| `patchText` | string | **必填** |


**补丁段落标记**（与 `tool_runtime.dart` 解析一致）：

- `*** Add File: <path>` — 新增文件，内容行以 `+` 开头。
- `*** Update File: <path>` — 修改；使用 `@@` 开始 hunk，行前缀： ``（上下文）、`-`（删）、`+`（增）。
- `*** Delete File: <path>` — 删除文件。
- `*** Move to: <newpath>` — 与 Update 配合表示移动（先写目标路径行）。
- `*** End of File` — 可放在 update hunk 内，表示该块应优先从文件尾定位。

**使用建议**：

- 修改已有文件前，先用 `read` 读取最新内容，再生成 patch。
- `apply_patch` 也支持 hashline 头部：`@@ replace 12#VK`、`@@ replace 12#VK 15#MB`、`@@ append 20#QR`、`@@ prepend 20#QR`。
- 使用 hashline 头部时，锚点必须直接复制自 `read` 输出，只保留 `LINE#ID`，不要带 `|内容`。
- 若自上次 `read` 后文件发生变化，`apply_patch` 会拒绝执行并要求重新读取。
- 若刚对同一文件执行过 `edit` / `apply_patch`，再次修改前最好先重新 `read`，不要复用旧上下文。
- `@@` 后可带一个简短上下文锚点（如函数名 / 类名 / 附近唯一行）帮助定位重复代码块。
- 尽量带足够的未修改上下文行，避免只给一两行导致定位失败。
- 空白同样参与匹配；缩进、行尾空格、换行差异都可能影响结果。
- patch 失败后应重新 `read` 目标文件，并用更大的上下文重新生成。

**Update 示例**：

```text
*** Update File: lib/a.dart
@@
- old line
+ new line
```

**Hashline 示例**：

```text
*** Update File: lib/a.dart
@@ replace 12#VK
- old line
+ new line
```

---

### 5. `list`

**作用**：在工作区下列出文件并渲染为树状文本。默认忽略常见目录（如 `.git/`、`node_modules/`、`build/`、`.dart_tool/` 等，见代码中 `_kDefaultWorkspaceIgnorePatterns`）。

**参数**：


| 参数       | 类型       | 说明         |
| -------- | -------- | ---------- |
| `path`   | string   | 可选，子目录；空为根 |
| `ignore` | string[] | 可选，额外忽略模式  |


**注意**：结果最多约 **100** 个文件（`_kToolResultLimit`），超出会截断。

**示例**：

```json
{ "path": "lib", "ignore": ["**/*.g.dart"] }
```

---

### 6. `glob`

**作用**：按 glob 模式搜索文件路径。

**参数**：


| 参数        | 类型     | 说明                   |
| --------- | ------ | -------------------- |
| `pattern` | string | **必填**，如 `**/*.dart` |
| `path`    | string | 可选，限定搜索根子路径          |


**示例**：

```json
{ "pattern": "**/test/**/*_test.dart", "path": "packages" }
```

---

### 7. `grep`

**作用**：用正则表达式按**行**搜索文件内容（经 `WorkspaceBridge.grepText` → Android `grepWorkspace`）。正则为 **Kotlin `Regex`**，与 ripgrep/PCRE 不完全相同。

**参数**：


| 参数        | 类型     | 说明                                                                 |
| --------- | ------ | ------------------------------------------------------------------ |
| `pattern` | string | **必填**，每行独立匹配                                                      |
| `path`    | string | 可选，必须是工作区内的**目录**（不能传单个文件路径；搜单文件请 `read` 或传父目录 + `include`/`glob`） |
| `include` | string | 可选，glob；与 `**glob` 二选一**（`include` 非空时优先）                          |
| `glob`    | string | 可选，`**include` 的别名**，方便与常见工具命名对齐                                   |


`**include` / `glob` 语义**：按**整条工作区相对路径**匹配（如 `lib/main.dart`），不是仅文件名。子目录下按扩展名过滤请用 `**/*.dart`；仅用 `*.dart` 只会匹配根目录下一层文件名。

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


| 参数     | 类型     | 说明               |
| ------ | ------ | ---------------- |
| `path` | string | **必填**，相对工作区根的路径 |


**返回字段**：`path`、`name`、`isDirectory`、`size`、`lastModified`（毫秒时间戳）、`mimeType`（若有）。

**示例**：

```json
{ "path": "lib/main.dart" }
```

---

### 9. `delete`

**作用**：删除文件或目录（目录递归删除）。需 `**edit` 权限**。

**适用场景**：

- 删除单个文件
- 删除整个文件夹
- 删除某个目录树下的所有内容（直接删该目录）

**参数**：


| 参数     | 类型     | 说明     |
| ------ | ------ | ------ |
| `path` | string | **必填** |


**示例**：

```json
{ "path": "tmp/old.txt" }
```

---

### 10. `rename`

**作用**：在同一父目录下重命名（仅改文件名）。需 `**edit` 权限**。若需跨目录路径变更，请用 `**move`**。

**参数**：


| 参数        | 类型     | 说明                  |
| --------- | ------ | ------------------- |
| `path`    | string | **必填**，原相对路径        |
| `newName` | string | **必填**，新文件名（不含 `/`） |


**注意**：

- `rename` 既可用于文件，也可用于目录。
- `newName` 只能是最终名字，不能带路径分隔符。
- 只改名、不换目录时优先用 `rename`；目录也要变化时改用 `move`。

**示例**：

```json
{ "path": "lib/foo.dart", "newName": "bar.dart" }
```

---

### 11. `move`

**作用**：将文件或目录移动到新的工作区相对路径（`toPath` 为最终路径，含文件名）。需 `**edit` 权限**。Android 上优先使用 `DocumentsContract.moveDocument`（API 24+），否则回退为复制后删除源。

**参数**：


| 参数         | 类型     | 说明          |
| ---------- | ------ | ----------- |
| `fromPath` | string | **必填**，源路径  |
| `toPath`   | string | **必填**，目标路径 |


**注意**：

- `move` 同时适用于文件和目录。
- 当你想“改路径”而不仅是“改名字”时，用 `move` 而不是 `rename`。
- `toPath` 是最终完整目标路径，不只是目标目录。

**示例**：

```json
{ "fromPath": "draft/a.txt", "toPath": "src/a.txt" }
```

---

### 12. `copy`

**作用**：复制文件或目录到另一路径（目录递归复制；平台限制深度与文件数）。需 `**edit` 权限**。

**参数**：


| 参数         | 类型     | 说明          |
| ---------- | ------ | ----------- |
| `fromPath` | string | **必填**，源路径  |
| `toPath`   | string | **必填**，目标路径 |


**注意**：

- `copy` 可复制单个文件，也可递归复制整个目录。
- 若目标已存在，工具会失败而不是覆盖。

**示例**：

```json
{ "fromPath": "lib/a.dart", "toPath": "lib/a_backup.dart" }
```

---

### 13. `todowrite`

**作用**：将待办列表写入当前会话并持久化。

**参数**：


| 参数      | 类型    | 说明                                                 |
| ------- | ----- | -------------------------------------------------- |
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


| 参数          | 类型    | 说明                                                                                       |
| ----------- | ----- | ---------------------------------------------------------------------------------------- |
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

**作用**：HTTP GET 获取 URL 正文。需 `**webfetch` 权限**（默认多为询问）。

**参数**：


| 参数    | 类型     | 说明     |
| ----- | ------ | ------ |
| `url` | string | **必填** |


**示例**：

```json
{ "url": "https://example.com/doc" }
```

---

### 16. `browser`

**作用**：在应用内打开工作区内的 **HTML** 页面（返回 `browser_page` 类附件）。

**参数**：


| 参数     | 类型     | 说明                                         |
| ------ | ------ | ------------------------------------------ |
| `path` | string | **必填**；可为目录，会尝试 `index.html` / `index.htm` |


**示例**：

```json
{ "path": "web/dist/index.html" }
```

---

### 17. `skill`

**作用**：按名称读取内置短技能说明（注入模型上下文）。

**参数**：


| 参数     | 类型     | 说明                                             |
| ------ | ------ | ---------------------------------------------- |
| `name` | string | **必填**；当前实现：`android_workspace`、`mobile_agent` |


**示例**：

```json
{ "name": "mobile_agent" }
```

---

### 18. `invalid`

**作用**：由模型或管线声明某次工具调用非法，用于自纠与展示。

**参数**：


| 参数      | 类型     | 说明     |
| ------- | ------ | ------ |
| `tool`  | string | **必填** |
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

**作用**：创建或续用子会话，使用指定子代理执行 `prompt`，返回最后助手输出（包在 `<task_result>` 中）。

**参数**：


| 参数              | 类型     | 说明                                                                        |
| --------------- | ------ | ------------------------------------------------------------------------- |
| `description`   | string | **必填**，任务标题                                                               |
| `prompt`        | string | **必填**，子会话用户消息                                                            |
| `subagent_type` | string | 可选，默认 `general`；与 `AgentRegistry` 名称一致：`build`、`plan`、`general`、`explore` |
| `task_id`       | string | 可选；传入已有子会话 ID 时，会续跑该子任务而不是新建会话                                            |


**示例**：

```json
{
  "description": "梳理 lib/core 依赖",
  "prompt": "只读分析 tool_runtime.dart 的依赖关系，简要输出。",
  "subagent_type": "explore",
  "task_id": "session_xxx"
}
```

---

## 实现与维护

- 工具注册：`lib/core/tool_runtime.dart` → `ToolRegistry.builtins()`。
- Agent 与权限：`lib/core/agents.dart`。
- 工作区桥接：`lib/core/workspace_bridge.dart`；`stat` / `delete` / `rename` / `move` / `copy` 在本地路径模式下直接走 Dart 文件系统，在受限平台工作区下走原生 MethodChannel。当前 Android 与 iOS 都已支持这些工作区文件操作。
- 若修改 `availableTools` 或 `PermissionRule`，请同步更新本文档。

