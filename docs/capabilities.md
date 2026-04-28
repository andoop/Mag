# Capabilities

This page is the product capability map for **Mag**. It explains what the app can do, how the agent is extended, and where to find deeper technical details.

## The Big Picture

Mag is a mobile agent workspace:

```text
Project -> Session -> Model -> Tools -> Permission -> Result
```

Each session belongs to a project. Each project has a workspace. The model can reason over that workspace through tools, and Mag keeps the user in control through visible tool calls and permission prompts.

## Models And Providers

Mag is provider-agnostic. It supports official APIs, aggregators, local inference, and custom OpenAI-compatible gateways.

| Provider | Type | Notes |
|----------|------|-------|
| Anthropic | Official API | Claude models. |
| DeepSeek | Official API | DeepSeek chat/coding models. |
| Google / Gemini | Official API | Gemini through the Google Generative AI OpenAI-compatible endpoint. |
| Mag | Hosted entry | Mag Zen free-model entry with optional public-token fallback. |
| OpenRouter | Aggregator | Many hosted models, including free and popular entries. |
| Groq | OpenAI-compatible | Fast inference endpoint. |
| Mistral | Official API | Mistral models. |
| Ollama | Local | Local models through an OpenAI-compatible endpoint. |
| OpenAI | Official API | OpenAI models. |
| GitHub Models | Hosted | GitHub-hosted model inference. |
| Vercel AI Gateway | Gateway | OpenAI-compatible AI gateway. |
| xAI | Official API | Grok models. |
| OpenAI Compatible | Custom | Bring LiteLLM, self-hosted gateways, proxies, or compatible providers. |

Model-related features include:

- Provider connection and API key configuration.
- Model discovery where the provider supports it.
- Recent model ordering.
- Free/latest model tags in the UI.
- Context usage display.
- Model-specific request normalization and tool routing.
- Support for providers that need compatibility handling.

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
项目 -> 会话 -> 模型 -> 工具 -> 权限 -> 结果
```

每个会话属于一个项目，每个项目有自己的工作区。模型通过工具理解和操作工作区，Mag 通过可见的工具调用和权限确认让用户保持控制权。

## 模型与供应商

Mag 不绑定单一模型供应商。它支持官方 API、聚合平台、本地推理和自定义 OpenAI-compatible 网关。

| 供应商 | 类型 | 说明 |
|--------|------|------|
| Anthropic | 官方 API | Claude 系列模型。 |
| DeepSeek | 官方 API | DeepSeek 对话/编程模型。 |
| Google / Gemini | 官方 API | 通过 Google Generative AI 的 OpenAI-compatible endpoint 使用 Gemini。 |
| Mag | 托管入口 | Mag Zen 免费模型入口，可选 public token fallback。 |
| OpenRouter | 聚合平台 | 多模型入口，包含免费和热门模型。 |
| Groq | OpenAI-compatible | 高速推理 endpoint。 |
| Mistral | 官方 API | Mistral 模型。 |
| Ollama | 本地模型 | 通过 OpenAI-compatible endpoint 使用本地模型。 |
| OpenAI | 官方 API | OpenAI 模型。 |
| GitHub Models | 托管模型 | GitHub 托管模型推理。 |
| Vercel AI Gateway | 网关 | OpenAI-compatible AI Gateway。 |
| xAI | 官方 API | Grok 模型。 |
| OpenAI Compatible | 自定义 | 接入 LiteLLM、自托管网关、代理或兼容供应商。 |

模型相关能力包括：

- 供应商连接与 API Key 配置。
- 支持时进行模型发现。
- 最近使用模型排序。
- 免费/最新模型标记。
- 上下文用量展示。
- 按模型能力做请求规范化和工具路由。
- 对兼容性要求特殊的供应商做适配。

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
