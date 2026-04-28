# Capabilities

This page is the product capability map for **Mag**. It explains what the app can do, how the agent is extended, and where to find deeper technical details.

## The Big Picture

Mag is a mobile agent workspace:

```text
Project -> Session -> Model -> Tools -> Permission -> Git / Files -> Result
```

The product thinking and agent architecture are inspired by **OpenCode**: sessions belong to workspaces, tools are explicit, permissions are visible, and the agent loop is treated as a real development workflow.

Each session belongs to a project. Each project has a workspace. The model can reason over that workspace through tools, and Mag keeps the user in control through visible tool calls, permission prompts, file previews, and Git state.

## Models And Providers

Mag is provider-agnostic. For the current model/provider landscape, use [models.dev](https://models.dev) as the reference. Mag focuses on making those models usable inside a mobile coding workflow.

Model-related features include:

- Provider connection and API key configuration.
- Model discovery where the provider supports it.
- Recent model ordering.
- Free/latest model tags in the UI.
- Context usage display.
- Model-specific request normalization and tool routing.
- Support for providers that need compatibility handling.
- Custom OpenAI-compatible endpoints for gateways, proxies, and local/self-hosted setups.

## Agent Modes

Mag exposes different tool sets depending on the agent role:

| Agent | Purpose | Tool Shape |
|-------|---------|------------|
| `build` | Default main-session coding agent | Full tool surface with write/edit capabilities and user-facing questions. |
| `general` | General sub-agent | Similar to build, with permission differences where configured. |
| `plan` | Planning mode | Read/search/question/tools for planning; destructive write operations are not exposed. |
| `explore` | Read-only exploration | Read/list/search/web/resource tools for understanding code without editing. |

See [ai-tools.md](ai-tools.md) for exact tool IDs and permission rules.

## Tool System

Mag tools are workspace-aware. File paths are relative to the project workspace root, not raw device paths.

| Category | Tools / Behaviors |
|----------|-------------------|
| Files | `read`, `list`, `stat`, `write`, `edit`, `apply_patch` |
| Search | `glob`, `grep` |
| File operations | `delete`, `rename`, `move`, `copy` |
| Work tracking | `task`, `todowrite`, permission/question cards |
| Network | `webfetch`, `download` |
| MCP | `list_mcp_resources`, `read_mcp_resource`, `list_mcp_prompts`, `get_mcp_prompt` |
| Skills | `skill` |
| Browser / misc | `browser`, `plan_exit`, `invalid` |

Sensitive operations are permissioned. For example, web access, downloads, `.env` access, and file edits can require explicit approval depending on the active agent and rule.

## Git

Git is a first-class part of Mag's mobile development story. The Android bridge is backed by JGit; the iOS bridge is backed by libgit2.

| Area | Capabilities |
|------|--------------|
| Repository | Discover repository, initialize repository, clone repository. |
| Status and review | Current branch, status, staged/unstaged diff, commit log, show commit. |
| Index and commits | Add paths, add all, unstage path, commit, amend commit. |
| Branches | List, create, delete, checkout target, checkout new branch. |
| History | Restore file, reset, merge, rebase, cherry-pick. |
| Remotes | List/add/set/remove/rename remotes, get remote URL, fetch, pull, push. |
| Config and auth | Git config values, Git identity, SSH keys, remote credentials. |

This matters because the agent can edit files, but the user still needs a real way to inspect, stage, commit, sync, and recover work.

## MCP

Mag includes MCP-facing tools for remote context and prompt extension:

- **List resources** from configured MCP servers.
- **Read resources** by server and URI.
- **List prompts** exposed by MCP servers.
- **Resolve prompts** with optional arguments.
- **OAuth foundation** for remote MCP servers that require authorization.

MCP support lets a mobile session pull context from external systems without hardcoding those systems into the app.

## Skills

Skills are reusable instruction packs. They help the agent handle specialized tasks consistently.

Mag discovers skills from:

- Built-in skills.
- `.opencode/skill`
- `.opencode/skills`
- `.claude/skills`
- `.agents/skills`

Loading a skill adds its instructions and bundled references into the conversation context. It does not secretly run scripts. This keeps Skills powerful but inspectable.

## Workspace And Files

Mag treats the workspace as the center of the product:

- Project home with recent projects.
- Sandbox project creation.
- Workspace file browser.
- Folder navigation and refresh.
- Markdown/HTML rendered preview and source view.
- PDF, image, text, and code previews.
- File attachments and `@` references in prompts.
- Workspace-relative paths for tools.

## Mobile Runtime

Mag uses native mobile capabilities where Flutter alone is not enough:

- Android system overlay floating window.
- iOS Picture-in-Picture style floating window foundation on iOS 15+.
- Mini, line, and full floating-window display modes.
- Native foreground service for floating-window reliability.
- Background running notification for active sessions.
- Localized notification text.
- Android notification and overlay permission handling.
- Tap-to-return from floating window to the main app.

## Local Runtime And Persistence

Mag keeps its working state local:

- SQLite stores sessions, messages, parts, todos, permissions, questions, and workspace indexes.
- Shared preferences store recent project ordering and lightweight preferences.
- A loopback HTTP server exposes local REST-style APIs and SSE-style events.
- The Flutter UI consumes those APIs through a typed local client.

This architecture makes the app easier to debug and easier to extend without coupling every UI component directly to the engine.

---

# 能力总览

本文是 **Mag** 的产品能力地图，用来说明这个移动端 Agent 到底能做什么、如何扩展，以及更深入的技术文档在哪里。

## 整体模型

Mag 是一个移动端 Agent 工作区：

```text
项目 -> 会话 -> 模型 -> 工具 -> 权限 -> Git / 文件 -> 结果
```

Mag 的产品思想和 Agent 架构参考 **OpenCode**：会话属于工作区，工具显式可见，权限明确展示给用户，Agent 循环被当成真实开发流程。

每个会话属于一个项目，每个项目有自己的工作区。模型通过工具理解和操作工作区，Mag 通过可见的工具调用、权限确认、文件预览和 Git 状态让用户保持控制权。

## 模型与供应商

Mag 不绑定单一模型供应商。当前模型和供应商生态建议直接参考 [models.dev](https://models.dev)。Mag 关注的是如何把这些模型放进移动端编程工作流中。

模型相关能力包括：

- 供应商连接与 API Key 配置。
- 支持时进行模型发现。
- 最近使用模型排序。
- 免费/最新模型标记。
- 上下文用量展示。
- 按模型能力做请求规范化和工具路由。
- 对兼容性要求特殊的供应商做适配。
- 自定义 OpenAI-compatible endpoint，用于接入网关、代理、本地或自托管服务。

## Agent 模式

Mag 会根据 Agent 角色暴露不同工具集合：

| Agent | 用途 | 工具形态 |
|-------|------|----------|
| `build` | 默认主会话编程 Agent | 完整工具面，包含写入/编辑和向用户提问。 |
| `general` | 通用子 Agent | 接近 build，但可按权限规则调整。 |
| `plan` | 规划模式 | 用于阅读、搜索、提问和规划，不暴露破坏性写操作。 |
| `explore` | 只读探索 | 用于理解代码，不编辑文件。 |

精确工具 ID 和权限规则见 [ai-tools.md](ai-tools.md)。

## 工具体系

Mag 的工具都以工作区为中心。文件路径相对项目工作区根目录，而不是设备绝对路径。

| 分类 | 工具 / 行为 |
|------|-------------|
| 文件 | `read`, `list`, `stat`, `write`, `edit`, `apply_patch` |
| 搜索 | `glob`, `grep` |
| 文件操作 | `delete`, `rename`, `move`, `copy` |
| 工作跟踪 | `task`, `todowrite`, 权限/问题卡片 |
| 网络 | `webfetch`, `download` |
| MCP | `list_mcp_resources`, `read_mcp_resource`, `list_mcp_prompts`, `get_mcp_prompt` |
| Skills | `skill` |
| 浏览器 / 其他 | `browser`, `plan_exit`, `invalid` |

敏感操作纳入权限体系。例如网页访问、下载、`.env` 访问、文件编辑等，可能根据当前 Agent 和规则要求用户显式确认。

## Git

Git 是 Mag 移动端开发体验中的一等能力。Android 侧基于 JGit，iOS 侧基于 libgit2。

| 领域 | 能力 |
|------|------|
| 仓库 | 发现仓库、初始化仓库、克隆仓库。 |
| 状态与审查 | 当前分支、status、staged/unstaged diff、commit log、commit 详情。 |
| 暂存与提交 | add paths、add all、unstage path、commit、amend commit。 |
| 分支 | 列出、创建、删除、checkout 目标、创建并 checkout 新分支。 |
| 历史 | restore 文件、reset、merge、rebase、cherry-pick。 |
| 远程 | 列出/添加/设置/删除/重命名 remote，获取 remote URL，fetch、pull、push。 |
| 配置与认证 | Git config、Git identity、SSH key、remote credential。 |

这很重要：Agent 可以修改文件，但用户仍然需要真正的方式来检查、暂存、提交、同步和恢复工作。

## MCP

Mag 内置面向 MCP 的工具，用来扩展远程上下文和 Prompt：

- 列出配置的 MCP Server 资源。
- 按 server 和 URI 读取资源。
- 列出 MCP Server 暴露的 Prompt。
- 使用可选参数解析 Prompt。
- 为需要授权的远程 MCP Server 提供 OAuth 流程基础。

MCP 让移动端会话可以从外部系统获取上下文，而不需要把这些系统写死在应用里。

## Skills

Skills 是可复用的任务说明包，用来让 Agent 更稳定地处理专门任务。

Mag 会从以下位置发现 Skills：

- 内置 Skills。
- `.opencode/skill`
- `.opencode/skills`
- `.claude/skills`
- `.agents/skills`

加载 Skill 会把说明和参考文件加入上下文，但不会偷偷执行脚本。这样既能增强 Agent，又保持可检查和可控。

## 工作区与文件

Mag 把工作区作为产品中心：

- 项目首页与最近项目。
- 沙盒项目创建。
- 工作区文件浏览器。
- 目录导航和刷新。
- Markdown/HTML 渲染预览与源码视图。
- PDF、图片、文本、代码预览。
- 文件附件和 `@` 引用。
- 工具使用工作区相对路径。

## 移动端运行时

Mag 在 Flutter 不够的地方使用原生移动能力：

- Android 系统悬浮窗。
- iOS 15+ Picture-in-Picture 风格小窗基础。
- 小窗迷你、单行、完整三种模式。
- 小窗可靠运行所需的原生前台服务。
- 活跃会话进入后台时的运行通知。
- 本地化通知文案。
- Android 通知权限和悬浮窗权限处理。
- 小窗点击回到主应用。

## 本地运行与持久化

Mag 将工作状态保存在本机：

- SQLite 保存会话、消息、片段、待办、权限、问题和工作区索引。
- SharedPreferences 保存最近项目排序和轻量偏好。
- 本机回环 HTTP 服务提供 REST 风格 API 和 SSE 风格事件。
- Flutter UI 通过类型化本地客户端消费这些 API。

这种架构让应用更容易调试，也更容易扩展，不需要让每个 UI 组件都直接耦合到 Agent 引擎。
