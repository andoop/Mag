# Mag

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-Dart-02569B?logo=flutter)](https://flutter.dev)

**Mag** (`mobile_agent`) is an open-source **mobile AI coding agent** built with Flutter. It brings an agent-style coding workflow to a phone: local projects, multi-turn sessions, model streaming, permissioned tools, file operations, workspace previews, and native mobile affordances such as Android floating windows and background status notifications.

Mag is designed for people who want to inspect, discuss, edit, and maintain code from a mobile device without reducing the experience to a simple chatbot.

**Languages:** [English](#english) | [中文](#中文)

---

## English

### Why Mag

Most AI coding tools assume a desktop IDE. Mag explores a different shape: a mobile-first agent shell that can run a complete coding loop around a local workspace while keeping user control visible. The app is not only a chat screen. It includes a project home, session history, workspace browser, file previews, permission prompts, tool execution, local persistence, and a loopback API for debugging and integration.

### Highlights

- **Mobile-first AI coding agent**: built for Android/iOS style interaction, not a desktop UI squeezed onto a phone.
- **Workspace-aware by default**: sessions are tied to a project workspace, and tools operate on paths relative to that workspace.
- **Full agent loop**: prompts, streaming assistant messages, reasoning/tool parts, permissions, file edits, todos, questions, and cancellation.
- **Native Android floating window**: keep the agent visible while switching to other apps, with compact and expanded display modes.
- **Local-first state**: sessions, messages, parts, todos, permission requests, and settings are stored locally with SQLite/shared preferences.
- **Debuggable architecture**: a loopback HTTP server and event stream expose session and message updates for the UI and tooling.
- **Bilingual UI and docs**: Chinese and English are maintained together for contributors and users.

### Feature Overview

| Area | Features |
|------|----------|
| **Projects** | Project home, recent projects, sandbox project creation, reopen project, rename/delete project, workspace-scoped state. |
| **Sessions** | New session landing page, session drawer, switch/create/rename/delete sessions, auto title after the first user message, busy/cancel state. |
| **Chat timeline** | Streaming messages, Markdown rendering, code highlighting, tool call visibility, permission/question cards, scroll-to-bottom behavior. |
| **Composer** | Multiline input, file references with `@`, attachment selection from workspace files, send/cancel behavior, keyboard dismissal after send. |
| **Agent tools** | Read/list/stat, write/edit/apply patch, glob/grep, file move/copy/delete/rename, todo updates, questions, web fetch/download, browser and MCP-style resource hooks. |
| **Permission model** | Tool permissions can ask/allow/deny; sensitive operations such as web/download/env access are guarded. |
| **Workspace browser** | Browse folders, refresh directory, open parent, preview Markdown/HTML as rendered view or source, view PDF/images/text/code. |
| **Floating window** | Android system overlay, native UI, mini/line/full display modes, drag, close, open-main-app action, foreground service notification. |
| **Background awareness** | Background running notification for active sessions, localized notification text, notification permission handling on Android 13+. |
| **Persistence** | SQLite database for sessions/messages/parts/todos/permissions/questions; shared preferences for recent project ordering. |
| **Local server** | Loopback HTTP APIs and SSE-style events such as `session.updated`, `message.*`, `permission.*`, `question.*`, `session.status`. |
| **Internationalization** | Chinese/English strings through `l(context, zh, en)`; user-facing docs are maintained bilingually. |

### Architecture At A Glance

```text
lib/ui/      Flutter screens: project home, chat, composer, timeline, browser
lib/store/   AppController, AppState, project/session navigation
lib/core/    Session engine, model gateway, tools, SQLite, local HTTP server
lib/sdk/     Typed client for the loopback server
android/     Native Android bridge, floating window service, notifications
ios/         iOS runner and platform bridge foundation
docs/        User, architecture, development, release, and tool docs
```

Mag uses Flutter for the main UI, native platform bridges for filesystem/mobile capabilities, a local session engine for the agent loop, and a local HTTP/SSE layer to decouple UI updates from core execution.

### Quick Start

**Requirements:**

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

### Documentation

| Document | Description |
|----------|-------------|
| [docs/README.md](docs/README.md) | Documentation index and bilingual maintenance notes |
| [docs/user-guide.md](docs/user-guide.md) | End-user flow: projects, sessions, files, settings |
| [docs/architecture.md](docs/architecture.md) | Layers, engine, local server, events, persistence |
| [docs/development.md](docs/development.md) | Setup, analysis/tests, native bridges, debugging |
| [docs/release.md](docs/release.md) | Signed APK packaging and release notes |
| [docs/ai-tools.md](docs/ai-tools.md) | Built-in agent tools, permissions, and path rules |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Contribution process and style |
| [SECURITY.md](SECURITY.md) | Vulnerability reporting |

### Download

- Signed APKs should be published through [GitHub Releases](https://github.com/andoop/Mag/releases).
- APK files should not be committed into git history.
- Local debug builds are available at `build/app/outputs/flutter-apk/app-debug.apk` after `flutter build apk --debug`.

### Security And Privacy

- Do not commit API keys, keystores, `android/key.properties`, credentials, or private workspace data.
- Workspace files and session data are local to the device unless a configured model/provider request sends content externally.
- Tool permissions are part of the product surface: keep sensitive file, network, and destructive operations explicit.
- Report vulnerabilities privately through [SECURITY.md](SECURITY.md).

### Contributing

Issues and pull requests are welcome. Please keep changes focused, run `dart analyze lib/`, and update both English and Chinese docs when user-facing behavior changes.

### License

Mag is released under the **MIT License**. See [LICENSE](LICENSE).

---

## 中文

**Mag**（Flutter 包名 `mobile_agent`）是一个开源的**移动端 AI 编程 Agent**。它把完整的 AI 编程闭环带到手机上：本地项目、多轮会话、模型流式输出、带权限的工具调用、文件读写与预览、工作区状态管理，以及 Android 小窗和后台运行通知等移动端能力。

Mag 的目标不是做一个简单聊天框，而是在移动设备上提供一个可观察、可控制、可维护的 Agent 工作台。

### 为什么做 Mag

大多数 AI 编程工具默认运行在桌面 IDE 中。Mag 探索的是另一种形态：面向移动端的 Agent Shell。用户可以在手机上进入项目、查看会话、让 Agent 读取和修改文件、确认敏感操作、查看工具调用，并在需要时通过小窗让任务继续在后台可见。

### 核心特点

- **移动端优先**：围绕手机交互设计，而不是把桌面 IDE 简单缩小。
- **工作区感知**：会话绑定到项目工作区，工具路径都相对工作区根目录。
- **完整 Agent 闭环**：提示词、流式消息、推理/工具片段、权限确认、文件编辑、待办、提问和取消。
- **Android 原生小窗**：切到其他应用时仍能观察 Agent 状态，支持迷你/单行/完整三种模式。
- **本地优先存储**：会话、消息、工具片段、待办、权限请求、问题和设置等都保存在本机。
- **可调试架构**：通过本机回环 HTTP 服务和事件流暴露会话、消息、权限和状态事件。
- **双语维护**：界面与文档同时维护中文和英文，方便用户与贡献者协作。

### 功能清单

| 模块 | 功能 |
|------|------|
| **项目** | 项目首页、最近项目、沙盒项目创建、重新打开项目、项目重命名/删除、按工作区隔离状态。 |
| **会话** | 新会话落地页、会话抽屉、创建/切换/重命名/删除会话、首条用户消息后自动标题、运行中/取消状态。 |
| **消息流** | 流式输出、Markdown 渲染、代码高亮、工具调用展示、权限/问题卡片、滚动到底部控制。 |
| **输入区** | 多行输入、`@` 引用工作区文件、从工作区选择附件、发送/取消、发送后收起键盘。 |
| **Agent 工具** | 读取/列目录/stat、写入/编辑/补丁、glob/grep、移动/复制/删除/重命名、待办、提问、网页获取/下载、浏览器和 MCP 风格资源入口。 |
| **权限模型** | 工具可 ask/allow/deny；网页、下载、环境文件和破坏性操作等敏感能力需要显式控制。 |
| **工作区浏览器** | 浏览目录、刷新、返回上级；Markdown/HTML 支持渲染视图与源码视图；支持 PDF、图片、文本、代码预览。 |
| **小窗** | Android 系统悬浮窗、原生 UI、迷你/单行/完整模式、拖拽、关闭、点击回到主应用、前台服务通知。 |
| **后台运行** | 有活跃会话时进入后台显示通知；通知文案中英文适配；支持 Android 13+ 通知权限。 |
| **持久化** | SQLite 保存会话、消息、片段、待办、权限、问题；SharedPreferences 保存最近项目排序。 |
| **本地服务** | 回环 HTTP API 和 SSE 风格事件，如 `session.updated`、`message.*`、`permission.*`、`question.*`、`session.status`。 |
| **国际化** | 通过 `l(context, zh, en)` 维护中文/英文界面文案；用户文档保持双语。 |

### 架构概览

```text
lib/ui/      Flutter 页面：项目首页、对话页、输入区、时间线、文件浏览器
lib/store/   AppController、AppState、项目/会话导航
lib/core/    会话引擎、模型网关、工具、SQLite、本地 HTTP 服务
lib/sdk/     本地回环服务的类型化客户端
android/     Android 原生桥接、小窗服务、通知能力
ios/         iOS Runner 与平台桥接基础
docs/        用户、架构、开发、发布与工具文档
```

Mag 使用 Flutter 构建主界面，通过原生桥接接入文件系统与移动端能力；核心层负责 Agent 循环、工具执行、数据库和本地 HTTP/SSE 事件；UI 通过本地客户端订阅状态变化。

### 快速开始

**要求：**

- 与 `pubspec.yaml` 匹配的 Flutter/Dart 环境
- Android SDK、真机或模拟器
- 在应用内配置模型服务商与 API Key

```bash
git clone https://github.com/andoop/Mag.git
cd Mag
flutter pub get
flutter run
```

正式打包请参考 [docs/development.md](docs/development.md) 和 [docs/release.md](docs/release.md)。

### 文档

| 文档 | 说明 |
|------|------|
| [docs/README.md](docs/README.md) | 文档索引与双语维护说明 |
| [docs/user-guide.md](docs/user-guide.md) | 用户流程：项目、会话、文件、设置 |
| [docs/architecture.md](docs/architecture.md) | 分层、引擎、本地服务、事件、持久化 |
| [docs/development.md](docs/development.md) | 环境、分析/测试、原生桥接、调试 |
| [docs/release.md](docs/release.md) | APK 签名、打包与发布说明 |
| [docs/ai-tools.md](docs/ai-tools.md) | 内置工具、权限与路径规则 |
| [CONTRIBUTING.md](CONTRIBUTING.md) | 贡献流程与代码风格 |
| [SECURITY.md](SECURITY.md) | 安全问题报告 |

### 下载

- 已签名 APK 建议通过 [GitHub Releases](https://github.com/andoop/Mag/releases) 分发。
- 不建议把 APK 文件直接提交到 git 历史。
- 本地调试包可通过 `flutter build apk --debug` 生成，路径为 `build/app/outputs/flutter-apk/app-debug.apk`。

### 安全与隐私

- 不要提交 API Key、签名文件、`android/key.properties`、凭据或私有工作区数据。
- 工作区文件和会话数据默认保存在本机；当你配置模型服务商后，相关上下文可能按请求发送给外部模型 API。
- 工具权限是产品能力的一部分：涉及敏感文件、网络访问和破坏性操作时应保持显式确认。
- 安全漏洞请按 [SECURITY.md](SECURITY.md) 私下报告。

### 参与贡献

欢迎提交 Issue 和 Pull Request。请保持改动聚焦，提交前运行 `dart analyze lib/`，并在用户可见行为变化时同步更新中文和英文文档。

### 许可证

Mag 使用 **MIT License** 发布，详见 [LICENSE](LICENSE)。

---

<p align="center">
  <sub>Mag — open-source mobile AI coding agent.</sub>
</p>
