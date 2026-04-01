# Mag

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-Dart-02569B?logo=flutter)](https://flutter.dev)

**Mag** (Flutter package: `mobile_agent`) is an **open-source mobile AI coding agent**. It runs a full agent loop on your device: multi-turn **sessions**, **tool execution** with permissions, **workspace**-aware file operations, and **streaming** LLM calls. A small **loopback HTTP server** exposes events and APIs for debugging and integration.

[Features](#features) · [Documentation](#documentation) · [Quick start](#quick-start) · [Security](#security--privacy) · [Contributing](#contributing) · [中文](#中文)

---

## Features

| Area | What you get |
|------|----------------|
| **Sessions** | Create/switch sessions, OpenCode-style default titles, optional **auto-title** after the first user message, **rename** and **delete** (with cascade cleanup). |
| **Project flow** | **Project home** with recent workspaces; enter a folder as workspace; **blank landing** until first message or explicit new session. |
| **Tools** | Read/write/edit files, glob/grep, patches, browser/fetch hooks, todos, questions, and more — see [docs/ai-tools.md](docs/ai-tools.md). |
| **Workspace UI** | **File browser** from the chat app bar: folders, PDF, images, **Markdown/HTML** (rendered vs **source**), syntax-highlighted text. |
| **Local server** | HTTP + SSE-style events (`session.updated`, `message.*`, permissions, …). |
| **Persistence** | SQLite for sessions, messages, parts, todos, etc. |
| **i18n** | UI strings wired for Chinese / English via `l(context, …)`. |

## Documentation

| Doc | Description |
|-----|-------------|
| [docs/README.md](docs/README.md) | Documentation index |
| [docs/user-guide.md](docs/user-guide.md) | How to use the app (projects, sessions, files) |
| [docs/architecture.md](docs/architecture.md) | Layers, engine, server, bridge |
| [docs/development.md](docs/development.md) | Setup, analyze, tests, native bridge |
| [docs/ai-tools.md](docs/ai-tools.md) | Built-in tools and agent permissions |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Pull requests and style |
| [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) | Community expectations |
| [SECURITY.md](SECURITY.md) | How to report vulnerabilities |

## Quick start

**Requirements:** Flutter/Dart per `pubspec.yaml`, **Android** as the primary target, and your own **API keys** where the provider requires them.

```bash
git clone https://github.com/andoop/Mag.git
cd Mag
flutter pub get
flutter run
```

Configure the model provider and keys in **Settings** inside the app.

**Developers:** run `dart analyze lib/` before submitting changes (see [CONTRIBUTING.md](CONTRIBUTING.md)).

## Repository layout

| Path | Role |
|------|------|
| `lib/app/` | Application entry (`MaterialApp`) |
| `lib/ui/` | Screens: `AppRoot`, project home, `HomePage` (+ parts: timeline, composer, file browser, …) |
| `lib/store/` | `AppController`, state, recent workspaces |
| `lib/core/` | Session engine, SQLite, local server, tools, models, workspace bridge |
| `lib/sdk/` | HTTP client for the loopback server |
| `android/` | Android app + **MethodChannel** workspace implementation |
| `docs/` | Extended documentation |

## Security & privacy

- **Do not commit** keystores, `key.properties`, API keys, or secrets. `.gitignore` covers common Android signing artifacts.
- You control how keys and workspace data are stored and transmitted to third-party LLM APIs.
- See [SECURITY.md](SECURITY.md) for vulnerability reporting.

## Contributing

Issues and pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) first: focused changes, `dart analyze`, and consistent style.

## License

This project is licensed under the **MIT License** — see [LICENSE](LICENSE).

---

## 中文

**Mag**（包名 `mobile_agent`）是一款**开源**的 Flutter **移动端 AI 编程助手**：多轮会话、带权限的工具执行、工作区文件联动、流式模型请求，以及本机 **HTTP + 事件流** 便于调试与扩展。

### 文档索引

| 文档 | 说明 |
|------|------|
| [docs/README.md](docs/README.md) | 文档总目录 |
| [docs/user-guide.md](docs/user-guide.md) | 使用说明（项目、会话、文件浏览器等） |
| [docs/architecture.md](docs/architecture.md) | 架构与模块说明 |
| [docs/development.md](docs/development.md) | 开发环境与分析/测试 |
| [docs/ai-tools.md](docs/ai-tools.md) | 内置 AI 工具与权限 |
| [CONTRIBUTING.md](CONTRIBUTING.md) | 贡献指南 |
| [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) | 社区行为准则 |
| [SECURITY.md](SECURITY.md) | 安全问题反馈方式 |

### 快速开始

```bash
git clone https://github.com/andoop/Mag.git
cd Mag
flutter pub get
flutter run
```

在应用内 **设置** 中配置模型服务商与 API Key。参与开发前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)，并运行 **`dart analyze lib/`**。

### 安全与隐私

勿将签名文件、密钥提交到仓库；第三方 API 与工作区数据的传输与保存由使用者自行负责。安全漏洞请按 [SECURITY.md](SECURITY.md) **私下**报告，勿发公开 Issue。

### 许可证

**MIT License**，见 [LICENSE](LICENSE)。

---

<p align="center">
  <sub>Mag — mobile AI coding agent, open source.</sub>
</p>
