# Features

Mag combines a mobile app, an agent runtime, workspace tools, native platform bridges, and local persistence into one mobile-first coding workflow.

## Product Map

| Area | Capabilities |
|------|--------------|
| Projects | Recent projects, sandbox project creation, project rename/delete, workspace-scoped state. |
| Sessions | New/switch/rename/delete sessions, auto-title, session drawer, stop/cancel, compaction, project memory hooks. |
| Models | Provider setup, API keys, discovery where supported, recent models, context usage, free/latest tags, OpenAI-compatible endpoints. |
| Timeline | Streaming responses, Markdown, code rendering, reasoning/tool summaries, permissions, questions, scroll controls. |
| Workspace files | Browse, refresh, preview Markdown/HTML/PDF/images/text/code/Office attachments, attach files, use `@` references. |
| Agent tools | Read/list/stat, write/edit/apply patch, search, move/copy/delete/rename, zip/unzip, variables, web fetch/download, todos, questions. |
| Office generation | Create DOCX, XLSX, and PPTX files on device from structured content. |
| Git | Discover/init/clone, status/diff/log/show, add/unstage/commit/amend, branch, checkout, restore, reset, merge, rebase, cherry-pick, remotes, fetch/pull/push, identity, SSH keys, credentials. |
| Device capabilities | Pick files, capture photos, record audio, record video, save, and share through native bridges. |
| AI web runtime | Generated HTML can call `window.MagNative` and captured file inputs for native file/media capabilities. |
| MCP | List/read resources, list/resolve prompts, OAuth foundation for remote servers. |
| Skills | Load reusable instructions from built-in and workspace-local skill directories. |
| Mobile runtime | Android floating window, foreground service, background notification, mini/line/full modes, tap-to-return, iOS PiP-style foundation. |
| Local runtime | SQLite persistence, local preferences, loopback HTTP APIs, SSE-style events. |

## Office Generation

Mag includes three generated artifact tools:

- `create_document` creates `.docx` reports, proposals, memos, and specs.
- `create_spreadsheet` creates `.xlsx` tables, trackers, plans, and formula sheets.
- `create_presentation` creates `.pptx` decks, summaries, and pitch presentations.

See [Document Generation](document-generation.md).

## Native Media And Device Capabilities

Mag exposes native mobile capabilities to the composer and AI-generated HTML pages:

- Device file picking.
- In-app photo capture.
- In-app audio recording.
- In-app video recording.
- Save/share foundations where enabled.

See [AI Web Runtime](web-runtime.md).

## Current Product Boundaries

- Mag is mobile-first; desktop workflows are not the center of the product.
- Generated Office files use predictable templates rather than arbitrary custom themes.
- Recording is implemented in-app, but advanced camera studio features are not the goal.
- Local-first does not mean offline-only; model providers receive the context you send to them.

---

# 功能总览

Mag 是移动端 Agent 工作台，核心能力包括项目/会话、模型接入、文件浏览与预览、Agent 工具、压缩/解压、Office 文档生成、手机 Git、端上媒体能力、AI 网页运行时、MCP、Skills、小窗和本地持久化。

重点新增能力：

- 生成 DOCX、XLSX、PPTX。
- 应用内拍照、录音、录制视频。
- AI 生成 HTML 可调用 `window.MagNative`。
- Android 小窗和 iOS PiP 风格基础能力。
