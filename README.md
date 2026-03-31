# Mag

**Mag** (package: `mobile_agent`) is a Flutter-based **mobile AI coding agent**. It brings a full agent loop—sessions, tools, workspace integration, and streaming LLM calls—to Android devices, with a local HTTP bridge for tooling and events.

---

## English

### Overview

Mag is designed for developers who want an **on-device experience** similar to modern coding agents: multi-turn sessions, tool execution with permissions, workspace awareness, and support for **OpenAI-compatible** and **aggregated** model providers (including optional public-token flows where supported).

### Features

- **Session engine** — Streaming completions, cancellation, retries, and continuation summaries.
- **Tool runtime** — Structured tool calls, patches, and observable execution aligned with agent-style semantics.
- **Local server** — Loopback HTTP server with SSE-style event streams for integration and debugging.
- **Workspace bridge** — Connects the agent to project/workspace context on device.
- **Persistence** — SQLite-backed storage for sessions and related state.
- **Internationalization** — UI strings prepared for localization (`i18n`).

### Architecture (high level)

| Layer | Role |
|--------|------|
| `lib/ui/` | Flutter UI (home, timeline, model/provider selection). |
| `lib/core/` | Session engine, prompts, tools, local server, workspace bridge, database models. |
| `lib/store/` | App state and orchestration. |
| `lib/sdk/` | Client utilities for the local server protocol. |

### Requirements

- **Flutter** SDK compatible with `sdk: '>=2.19.6 <3.0.0'` (see `pubspec.yaml`).
- **Android** — Primary target; network permission enabled for LLM APIs.
- Your own **API keys** where required by the provider you choose.

### Getting started

```bash
git clone https://github.com/andoop/Mag.git
cd Mag
flutter pub get
flutter run
```

Configure model provider and API keys inside the app as documented in the UI.

### Security & privacy

- **Do not commit** keystores, `key.properties`, or API keys. This repository’s `.gitignore` excludes common Android signing artifacts.
- You are responsible for how API keys and workspace data are stored and transmitted.

### Contributing

Issues and pull requests are welcome. Please keep changes focused, run `dart analyze`, and match existing code style.

### License

This project is licensed under the **MIT License** — see [LICENSE](LICENSE).

---

## 中文

### 项目简介

**Mag**（工程包名 `mobile_agent`）是一款基于 **Flutter** 的**移动端 AI 编程代理**应用。它在 Android 上提供完整的智能体闭环：多轮会话、工具调用、工作区联动，以及面向 LLM 的流式请求；并通过本机 **HTTP 服务** 提供事件与集成能力。

### 功能亮点

- **会话引擎** — 流式输出、取消与重试、续聊摘要等能力。
- **工具运行时** — 结构化工具调用与可观测执行流程。
- **本地服务** — 回环地址上的 HTTP 服务，支持类 SSE 的全局/会话事件。
- **工作区桥接** — 将代理与设备上的工程/工作区上下文关联。
- **持久化** — 使用 SQLite 存储会话及相关数据。
- **国际化** — UI 文案通过 `i18n` 组织，便于扩展语言。

### 架构概览

| 层级 | 说明 |
|------|------|
| `lib/ui/` | Flutter 界面（主页、时间线、模型与 Provider 选择等）。 |
| `lib/core/` | 会话引擎、提示词、工具、本地服务、工作区桥接与数据模型。 |
| `lib/store/` | 应用状态与业务流程编排。 |
| `lib/sdk/` | 本地服务协议的客户端封装。 |

### 环境要求

- 与 `pubspec.yaml` 中声明一致的 **Flutter / Dart** 版本。
- 以 **Android** 为主要运行平台；应用已声明网络权限以访问模型 API。
- 根据所选服务商配置 **API Key**（若该服务商需要）。

### 快速开始

```bash
git clone https://github.com/andoop/Mag.git
cd Mag
flutter pub get
flutter run
```

在应用内完成模型 Provider 与密钥等配置。

### 安全与隐私

- **切勿**将签名文件、`key.properties`、API 密钥等提交到仓库；本仓库已用 `.gitignore` 忽略常见 Android 签名相关文件。
- 请自行评估 API 密钥与工作区数据的存储与传输方式。

### 参与贡献

欢迎提交 Issue 与 Pull Request。建议改动保持单一职责，提交前执行 `dart analyze`，并遵循现有代码风格。

### 许可证

本项目采用 **MIT 许可证**，详见 [LICENSE](LICENSE)。

---

<p align="center">
  <sub>Mag — build your mobile coding agent workflow.</sub>
</p>
