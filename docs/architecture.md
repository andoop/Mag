# Architecture

High-level design of **Mag** (`mobile_agent`). Paths are under `lib/` unless noted.

## Layered overview

```
┌─────────────────────────────────────────────────────────────┐
│  lib/ui/          Flutter widgets (home_page, app_root, …)   │
├─────────────────────────────────────────────────────────────┤
│  lib/store/       AppController, AppState, recents store     │
├─────────────────────────────────────────────────────────────┤
│  lib/sdk/         LocalServerClient (HTTP to loopback)       │
├─────────────────────────────────────────────────────────────┤
│  lib/core/        Session engine, tools, DB, local HTTP      │
│                   WorkspaceBridge → platform MethodChannel   │
└─────────────────────────────────────────────────────────────┘
```

| Layer | Responsibility |
|-------|----------------|
| **UI** | `AppRoot` switches project home vs `HomePage`. Timeline, composer, drawers, file browser, settings sheets. |
| **Store** | Owns `SessionEngine`, `LocalServer`, `WorkspaceBridge`; merges SSE events into `AppState`; workspace/session navigation. |
| **SDK** | Typed HTTP client: sessions, messages, prompts, model config, permissions, `PATCH`/`DELETE` session, etc. |
| **Core** | SQLite (`AppDatabase`), `SessionEngine` (prompt loop, tools, compaction, title policy), `LocalServer` (routes + SSE), `ToolRegistry`, `ModelGateway`. |

## Session engine

- **Create session** — Default title via `SessionTitlePolicy` (aligned with OpenCode-style ISO timestamps).
- **Prompt** — Streams assistant parts; persists messages/parts; optional **auto title** from model after first user message when title still matches the default pattern.
- **Subtasks / child sessions** — Created with child default titles; auto-title generation is skipped for child patterns.
- **Compaction** — Summarizes context; updates session metadata.
- **Events** — `session.updated`, `session.deleted`, `message.*`, `permission.*`, `question.*`, `session.status`, etc., tagged with workspace `directory` (tree URI) for filtering.

## Local HTTP server

- Binds **loopback** only; `AppController` connects via `LocalServerClient`.
- **SSE** — `/global/event` (and `/event`) stream JSON events for the UI.
- **REST-style** — Workspaces, sessions, messages, async prompt, cancel, compact, session `PATCH` (rename), `DELETE` (cascade delete), workspace file bytes for previews, etc.

## Persistence

- **SQLite** — Sessions, messages, parts, todos, permission/question requests, workspace index tables, settings key-value.
- **Shared preferences** — Recent workspace ordering for the project home.

## Workspace bridge

- **Android** (Kotlin) implements `listDirectory`, `readText`, `readBytes`, search/grep, and file mutations used by tools.
- Dart **`WorkspaceBridge`** caches directory listings; UI file browser calls `listDirectory` with `force: true` on refresh.

## Internationalization

- UI strings use `l(context, zh, en)` pattern in `lib/ui/i18n.dart` and call sites.

---

## 中文概要

- **UI**：`AppRoot` 在项目首页与对话页之间切换；时间线、输入区、抽屉、文件浏览器等。
- **Store**：持有引擎与本地服务，订阅 SSE 更新 `AppState`，负责进入/离开工作区与会话切换。
- **Core**：SQLite 持久化、`SessionEngine` 对话与工具闭环、`LocalServer` 提供 HTTP 与事件流。
- **WorkspaceBridge**：通过 **MethodChannel** 调用原生实现目录列举与文件读写；工具与文件浏览器共用。

更多工具细节见 [ai-tools.md](ai-tools.md)。
