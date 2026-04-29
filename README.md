# Mag

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-Dart-02569B?logo=flutter)](https://flutter.dev)
[![Mobile Agent](https://img.shields.io/badge/AI-Mobile%20Coding%20Agent-7C3AED)](#english)

**Mag** (`mobile_agent`) is an open-source **mobile AI coding agent**: a pocket-sized agent workspace for reading, understanding, editing, and shipping code from your phone.

It is not "chat with a model on mobile." Mag combines projects, sessions, model providers, Git, tool execution, permissions, workspace files, MCP resources, Skills, local persistence, and native mobile background/mini-window experiences into one mobile-first agent workflow.

**Languages:** [English](#english) | [中文](#中文)  
**Docs:** [User Guide](docs/user-guide.md) · [Capabilities](docs/capabilities.md) · [Architecture](docs/architecture.md) · [AI Tools](docs/ai-tools.md)

## Screenshots

<p align="center">
  <img src="images/home.jpg" alt="Project home" width="180" />
  <img src="images/newsession.jpg" alt="New session landing" width="180" />
  <img src="images/messages.jpg" alt="Agent message timeline" width="180" />
  <img src="images/workspace.jpg" alt="Workspace file browser" width="180" />
</p>

<p align="center">
  <img src="images/provider.jpg" alt="Provider settings" width="180" />
  <img src="images/model.jpg" alt="Model selection" width="180" />
  <img src="images/setting.jpg" alt="App settings" width="180" />
</p>

---

## English

### What Makes It Different

Mag's product thinking and agent architecture are inspired by **OpenCode**: sessions are workspace-centered, tools are explicit, permissions are visible, and the agent loop is treated as a real development workflow instead of a decorative chat feature.

Mag is built around a simple loop:

```text
Open a project -> choose a model -> ask the agent -> approve tools -> inspect code/Git -> keep going
```

The important part is not only that a model can answer. The important part is that Mag gives the model a real workspace, shows what it is doing, asks before sensitive actions, remembers sessions locally, and stays useful even when you leave the app.

### Highlights

- **Pocket agent workspace**: project home, recent projects, session history, file browser, model settings, and agent timeline in one mobile UI.
- **Bring your own model**: provider/model metadata follows the ecosystem tracked by [models.dev](https://models.dev), with custom OpenAI-compatible endpoints for your own gateway.
- **Agent tools with guardrails**: read, search, edit, patch, move, copy, delete, download, web fetch, todos, questions, MCP resources/prompts, and Skills with explicit permissions.
- **Git on mobile**: initialize, clone, inspect status/diff/log, stage, commit/amend, branch, checkout, restore, reset, merge, fetch, pull, push, rebase, cherry-pick, and manage remotes/credentials from the mobile app.
- **MCP and Skills ready**: connect remote MCP resources/prompts, and load workspace-local or built-in Skills for repeatable expert workflows.
- **Native mobile presence**: Android system overlay and iOS Picture-in-Picture style mini-window foundation, plus background running status where the platform allows it.
- **Local-first memory**: projects, sessions, messages, tool parts, permissions, questions, todos, and settings persist locally.
- **Observable by design**: loopback HTTP APIs and SSE-style events make the agent engine easier to debug, integrate, and extend.
- **Bilingual from the start**: Chinese and English UI/docs are maintained together.

### Capability Map

| Capability | What Mag Provides |
|------------|-------------------|
| **Models** | Provider/model ecosystem reference via [models.dev](https://models.dev), plus app-side connection, discovery, context usage, and custom compatible endpoints. |
| **Model UX** | Provider connection, model discovery, recent models, free/latest tags, context usage, model-specific tool routing. |
| **Projects** | Sandbox projects, recent project home, create/open/rename/delete, workspace-scoped sessions and files. |
| **Git** | Native Git bridge for repository discovery, clone/init, status/diff/log, staging, commits, branches, remotes, sync, rebase, cherry-pick, reset/restore. |
| **Sessions** | Blank landing, create/switch/rename/delete, auto-title after first user message, busy/cancel/compact flow. |
| **Timeline** | Streaming content, Markdown, code highlighting, reasoning/tool summaries, permission cards, questions, scroll controls. |
| **Workspace Files** | Browse folders, preview Markdown/HTML/PDF/images/text/code, attach files, reference files with `@`. |
| **Agent Tools** | Read/list/stat, write/edit/apply patch, glob/grep, move/copy/delete/rename, web fetch/download, todos, questions. |
| **MCP** | List/read MCP resources, list/resolve MCP prompts, remote MCP OAuth flow foundation. |
| **Skills** | Load built-in and workspace-local Skills from `.opencode`, `.claude`, and `.agents` directories. |
| **Mobile Runtime** | Android overlay, iOS PiP foundation, foreground/background status, localized notification text. |
| **Storage** | SQLite for agent data, shared preferences for recents, secure/local settings where appropriate. |
| **Extensibility** | Local HTTP server, typed SDK client, MethodChannel workspace bridge, clear docs for tools and architecture. |

### Models

Mag does not try to hard-code the whole model universe into this README. For the current provider/model landscape, see [models.dev](https://models.dev). In the app, Mag focuses on the workflow around models: provider connection, model discovery where supported, recent models, context usage, and compatibility handling for OpenAI-compatible gateways.

### MCP And Skills

Mag treats tools as part of the product, not hidden magic.

- **MCP resources**: discover and read resources exposed by configured remote MCP servers.
- **MCP prompts**: list and resolve prompt templates from MCP servers.
- **Skills**: load domain-specific instructions and reference files from built-in Skills or workspace folders.
- **Workspace locations**: `.opencode/skill`, `.opencode/skills`, `.claude/skills`, and `.agents/skills`.
- **Permission-aware**: Skills load instructions into context; they do not secretly execute scripts.

### Git

Mag treats Git as a first-class mobile development capability. The app includes native Git bridges on Android and iOS so a mobile project can still behave like a real repository.

- **Repository basics**: discover, initialize, clone, inspect current branch, read status.
- **Review changes**: staged/unstaged diff, commit log, show commit details.
- **Stage and commit**: add paths, add all, unstage, commit, amend.
- **Branch work**: list/create/delete branches, checkout existing target, checkout new branch.
- **History operations**: restore files, reset, merge, rebase, cherry-pick.
- **Remote sync**: list/add/set/remove/rename remotes, fetch, pull, push.
- **Credentials**: Git identity, SSH keys, and remote credentials are managed from settings.

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
| [docs/capabilities.md](docs/capabilities.md) | Product capability map: providers, MCP, Skills, tools, mobile runtime |
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

**Mag**（Flutter 包名 `mobile_agent`）是一个开源的**移动端 AI 编程 Agent**：一个装进口袋里的 Agent 工作区，用来在手机上阅读、理解、修改和维护代码。

它不是“手机上的模型聊天框”。Mag 把项目、会话、模型供应商、Git、工具执行、权限确认、工作区文件、MCP 资源、Skills、本地持久化，以及原生移动端后台/小窗体验组合成一个移动端优先的 Agent 工作流。

### Mag 的工作方式

Mag 的整体思想和 Agent 架构参考 **OpenCode**：会话围绕工作区组织，工具显式可见，权限明确交给用户确认，Agent 循环被当成真实开发流程，而不是聊天框装饰。

```text
打开项目 -> 选择模型 -> 提问给 Agent -> 审批工具 -> 查看代码/Git -> 继续迭代
```

关键不只是“模型能回答”，而是 Mag 给模型一个真实工作区，把 Agent 正在做什么展示出来，在敏感操作前询问你，把会话和状态保存在本机，并且在你离开应用时仍能继续观察任务。

### 核心亮点

- **口袋里的 Agent 工作台**：项目首页、最近项目、会话历史、文件浏览器、模型设置和 Agent 时间线整合在一个移动端 UI 中。
- **自带多模型生态支持**：供应商/模型元信息参考 [models.dev](https://models.dev)，同时支持自定义 OpenAI-compatible endpoint。
- **有护栏的 Agent 工具系统**：读文件、搜索、编辑、补丁、移动、复制、删除、下载、网页获取、待办、提问、MCP 资源/Prompt、Skills，均纳入权限体系。
- **手机上的 Git 工作流**：初始化、克隆、status/diff/log、暂存、提交/amend、分支、checkout、restore、reset、merge、fetch、pull、push、rebase、cherry-pick、remote/credential 管理。
- **MCP 与 Skills 原生融入**：连接远程 MCP 资源/Prompt，加载工作区或内置 Skills，让常见任务变成可复用的专家流程。
- **移动端存在感**：Android 系统悬浮窗、iOS Picture-in-Picture 风格小窗基础，以及平台允许范围内的后台运行状态。
- **本地优先记忆**：项目、会话、消息、工具片段、权限、问题、待办和设置都持久化在本机。
- **可观测、可扩展**：本机 HTTP API 与 SSE 风格事件让 Agent 引擎更容易调试、集成和扩展。
- **双语维护**：中文和英文 UI/文档同步维护，方便用户使用，也方便贡献者参与。

### 能力地图

| 能力 | Mag 提供什么 |
|------|--------------|
| **模型** | 通过 [models.dev](https://models.dev) 作为模型/供应商生态参考，应用侧负责连接、发现、上下文用量和自定义兼容 endpoint。 |
| **模型体验** | 供应商连接、模型发现、最近模型、免费/最新标记、上下文用量、按模型能力路由工具。 |
| **项目** | 沙盒项目、最近项目首页、创建/打开/重命名/删除、按工作区隔离会话和文件。 |
| **Git** | 原生 Git 桥接，支持仓库发现、clone/init、status/diff/log、暂存、提交、分支、remote、同步、rebase、cherry-pick、reset/restore。 |
| **会话** | 空白落地页、创建/切换/重命名/删除、首条用户消息后自动标题、运行/取消/压缩。 |
| **消息流** | 流式内容、Markdown、代码高亮、推理/工具摘要、权限卡片、问题卡片、滚动控制。 |
| **工作区文件** | 浏览目录、预览 Markdown/HTML/PDF/图片/文本/代码、选择附件、用 `@` 引用文件。 |
| **Agent 工具** | read/list/stat、write/edit/apply_patch、glob/grep、move/copy/delete/rename、webfetch/download、todos、question。 |
| **MCP** | 列出/读取 MCP 资源，列出/解析 MCP Prompt，远程 MCP OAuth 流程基础。 |
| **Skills** | 从内置 Skills 和 `.opencode`、`.claude`、`.agents` 目录加载专家工作流。 |
| **移动运行时** | Android 悬浮窗、iOS PiP 基础、前台/后台状态、本地化通知文案。 |
| **存储** | SQLite 保存 Agent 数据，SharedPreferences 保存最近项目，敏感配置按平台能力处理。 |
| **扩展性** | 本地 HTTP 服务、类型化 SDK 客户端、MethodChannel 工作区桥接、清晰的工具和架构文档。 |

### 模型

Mag 不把模型宇宙硬编码进 README。当前模型和供应商生态可直接参考 [models.dev](https://models.dev)。在应用内，Mag 更关注模型周边的工作流：供应商连接、支持时的模型发现、最近模型、上下文用量，以及对 OpenAI-compatible 网关的兼容处理。

### MCP 与 Skills

Mag 把工具能力当成产品核心，而不是藏在模型背后的黑盒。

- **MCP Resources**：发现并读取远程 MCP Server 暴露的资源。
- **MCP Prompts**：列出并解析远程 MCP Prompt 模板。
- **Skills**：加载领域专用说明和参考文件，形成可复用工作流。
- **工作区目录**：支持 `.opencode/skill`、`.opencode/skills`、`.claude/skills`、`.agents/skills`。
- **权限感知**：Skill 只把说明和参考资料加载进上下文，不会偷偷执行脚本。

### Git

Mag 把 Git 当成移动端开发的核心能力，而不是附属功能。Android 和 iOS 都有原生 Git 桥接，让手机里的项目仍然像一个真正的代码仓库。

- **仓库基础**：发现仓库、初始化、克隆、查看当前分支和 status。
- **查看改动**：staged/unstaged diff、commit log、commit 详情。
- **暂存与提交**：add paths、add all、unstage、commit、amend。
- **分支工作流**：列出/创建/删除分支，checkout 目标，创建并 checkout 新分支。
- **历史操作**：restore 文件、reset、merge、rebase、cherry-pick。
- **远程同步**：列出/添加/设置/删除/重命名 remote，fetch、pull、push。
- **凭据管理**：在设置中维护 Git identity、SSH key 和远程认证信息。

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
| [docs/capabilities.md](docs/capabilities.md) | 产品能力地图：模型供应商、MCP、Skills、工具、移动运行时 |
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
