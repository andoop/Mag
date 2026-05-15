# Mag

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-Dart-02569B?logo=flutter)](https://flutter.dev)
[![Mobile Agent](https://img.shields.io/badge/AI-Mobile%20Coding%20Agent-7C3AED)](#features)

**Mag** (`mobile_agent`) is an open-source **mobile AI coding agent**. It gives an AI agent a real on-device workspace: projects, sessions, files, Git, tools, permissions, model providers, MCP, Skills, and native mobile runtime capabilities.

Mag is not just mobile chat. It is a phone-sized agent workbench for reading, editing, reviewing, and shipping code while keeping user approval and local state visible.

**Demo:** [Watch the Mag app demo video](docs/assets/mag-app-demo.mp4)  
**Docs:** [User Guide](docs/user-guide.md) · [Capabilities](docs/capabilities.md) · [Architecture](docs/architecture.md) · [AI Tools](docs/ai-tools.md)  
**中文:** [中文简介](#中文简介)

## Features

| Area | What Mag Provides |
|------|-------------------|
| **Workspace** | Recent projects, sandbox project creation, file browser, file preview, attachments, and `@` file references. |
| **Agent Sessions** | Workspace-scoped sessions, session drawer, new/rename/delete/switch, auto-title, stop/cancel, compaction and project memory hooks. |
| **Models** | Provider setup, API keys, model discovery where supported, recent models, context usage, model tags, and custom OpenAI-compatible endpoints. |
| **Timeline** | Streaming answers, Markdown/code rendering, reasoning and tool summaries, permission cards, question cards, and scroll controls. |
| **Agent Tools** | Read/list/stat, write/edit/apply patch, search, move/copy/delete/rename, web fetch/download, todos, questions, MCP resources/prompts, and Skills. |
| **Git** | Native mobile Git: discover/init/clone, status/diff/log/show, add/unstage/commit/amend, branch, checkout, restore, reset, merge, rebase, cherry-pick, remotes, fetch/pull/push, identity, SSH keys, and credentials. |
| **Device Capabilities** | Pick files, capture photos, record audio, record video, save files, and share from native Android/iOS bridges. |
| **AI Web Runtime** | AI-generated HTML can call `window.MagNative.pickFiles`, `capturePhoto`, `recordAudio`, and `recordVideo`; capture file inputs are bridged to native capabilities. |
| **Mobile Runtime** | Android floating window, foreground service, background notification, mini/line/full overlay modes, tap-to-return, and iOS Picture-in-Picture style foundation. |
| **MCP And Skills** | Remote MCP resources/prompts, OAuth foundation, and reusable Skills from built-in or workspace-local directories. |
| **Local First** | SQLite-backed sessions/messages/tool parts/permissions/todos/questions, local preferences, loopback HTTP APIs, and SSE-style events. |

## Architecture

```text
Flutter UI -> Local SDK client -> Session engine -> Tools / Git / Files / MCP / Skills
                         |              |
                         |              +-> SQLite and local persistence
                         +-> Native Android/iOS bridges for files, media, Git, and mobile runtime
```

Mag uses Flutter for the app UI, a local session engine for the agent loop, native bridges for platform capabilities, and a loopback HTTP/SSE layer so UI and engine state stay observable.

## Quick Start

Requirements:

- Flutter/Dart compatible with `pubspec.yaml`
- Android SDK/device or emulator for the primary target
- Model provider credentials configured inside the app

```bash
git clone https://github.com/andoop/Mag.git
cd Mag
flutter pub get
flutter run
```

For release packaging, see [docs/development.md](docs/development.md) and [docs/release.md](docs/release.md).

## Documentation

| Document | Description |
|----------|-------------|
| [docs/user-guide.md](docs/user-guide.md) | End-user flow: projects, sessions, files, media attachments, settings, and mobile mini-window. |
| [docs/capabilities.md](docs/capabilities.md) | Product capability map: models, tools, Git, MCP, Skills, device capabilities, and mobile runtime. |
| [docs/ai-tools.md](docs/ai-tools.md) | Built-in agent tools, permissions, and path rules. |
| [docs/architecture.md](docs/architecture.md) | Layers, engine, local server, events, and persistence. |
| [docs/development.md](docs/development.md) | Setup, analysis/tests, native bridges, and debugging. |
| [docs/release.md](docs/release.md) | Signed APK packaging and release notes. |

## Security And Privacy

- Do not commit API keys, keystores, `android/key.properties`, credentials, or private workspace data.
- Workspace files and session data are local by default; configured model providers may receive the context you send in requests.
- Sensitive tools, file access, network access, and destructive actions should remain explicit and permissioned.
- Report vulnerabilities privately through [SECURITY.md](SECURITY.md).

## 中文简介

**Mag** 是一个开源的**移动端 AI 编程 Agent**：它不是“手机上的聊天框”，而是一个装进口袋里的 Agent 工作台。你可以在手机上创建项目、打开工作区、选择模型、让 Agent 阅读和修改代码、审批工具调用、查看 Git 改动，并在离开应用后继续通过小窗观察任务。

### 核心能力

| 模块 | 能力 |
|------|------|
| **项目与会话** | 最近项目、沙盒项目、会话抽屉、新建/切换/重命名/删除、自动标题、停止/取消、压缩和项目记忆入口。 |
| **模型接入** | 供应商配置、API Key、模型发现、最近模型、上下文用量、模型标签、自定义 OpenAI-compatible endpoint。 |
| **工作区文件** | 文件浏览、Markdown/HTML/PDF/图片/文本/代码预览、附件、`@` 文件引用、工作区相对路径。 |
| **Agent 工具** | 读写文件、搜索、补丁、移动/复制/删除/重命名、网页获取/下载、待办、提问、MCP、Skills，并接入权限体系。 |
| **手机 Git** | 仓库发现、init/clone、status/diff/log/show、暂存、提交/amend、分支、checkout、restore、reset、merge、rebase、cherry-pick、remote、fetch/pull/push、凭据和 SSH key。 |
| **端上能力** | 选择文件、拍照、录音、录制视频、保存文件、分享，Android/iOS 均通过原生桥接实现。 |
| **AI 网页运行时** | AI 生成的 HTML 可通过 `window.MagNative` 调用选文件、拍照、录音、录像；带 capture 的文件输入会桥接到原生能力。 |
| **移动运行时** | Android 悬浮窗、前台服务、后台通知、迷你/单行/完整模式、点击回到应用，以及 iOS PiP 风格基础能力。 |
| **MCP 与 Skills** | 远程 MCP 资源/Prompt、OAuth 基础、内置或工作区本地 Skills。 |
| **本地优先** | SQLite 保存会话、消息、工具片段、权限、问题、待办；本机 HTTP API 与 SSE 事件便于调试和扩展。 |

### 快速开始

```bash
git clone https://github.com/andoop/Mag.git
cd Mag
flutter pub get
flutter run
```

正式打包请参考 [docs/development.md](docs/development.md) 和 [docs/release.md](docs/release.md)。

## License

Mag is released under the **MIT License**. See [LICENSE](LICENSE).
