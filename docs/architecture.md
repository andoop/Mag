# Architecture

Mag is a Flutter app backed by a local agent runtime, native platform bridges, and local persistence.

## High-Level Flow

```text
Flutter UI
  -> Local SDK client
  -> Session engine
  -> Tools / Git / Office generation / MCP / Skills
  -> Workspace bridge and native Android/iOS capabilities
  -> SQLite and local preferences
```

## Main Layers

| Layer | Responsibility |
|-------|----------------|
| Flutter UI | Project home, chat, composer, timeline, file browser, previews, settings. |
| Store/state | Project/session navigation, busy state, selected model, UI orchestration. |
| Session engine | Message lifecycle, model calls, tool routing, permissions, persistence. |
| Tool runtime | Workspace file operations, Git, web fetch/download, Office generation, MCP, Skills. |
| Local server/client | Loopback APIs and SSE-style events between engine and UI surfaces. |
| Native bridges | Android/iOS workspace access, media capabilities, Git integrations, mobile runtime. |
| Persistence | SQLite for durable agent data; preferences for lightweight local settings. |

## Native Capabilities

Mag uses native code where Flutter alone is not enough:

- Android/iOS file and workspace bridges.
- Camera, microphone, audio/video recording.
- Git bridge implementations.
- Android floating window and foreground service.
- iOS Picture-in-Picture style foundation.

## Local-First Model

Projects, sessions, messages, permissions, todos, and tool parts are stored locally. Model providers receive only the context needed for requests configured by the user.

## Extension Points

- Add a tool in the tool registry.
- Add a native capability in the platform bridge and expose it through Dart.
- Add an AI web runtime alias through `window.MagNative`.
- Add a Skill directory for reusable task instructions.
- Add docs in the same PR as user-visible behavior changes.

---

# 架构

Mag 的核心结构是 Flutter UI + 本地 Agent 引擎 + 原生平台桥接 + 本地持久化。UI 不直接承担所有业务逻辑，而是通过本地客户端和事件流消费会话状态；工具运行时负责文件、Git、Office 生成、MCP 和 Skills 等能力。
