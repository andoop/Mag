# Mag Documentation

This folder contains the long-form documentation for **Mag** (`mobile_agent`), an open-source mobile AI coding agent. Start with the [root README](../README.md) for the product overview, then use the documents below for user flows, architecture, development, release, and tool details.

Mag documentation is maintained bilingually. User-facing concepts should be understandable in both English and Chinese, especially for features that affect permissions, file operations, background execution, or mobile platform behavior.

## Document Map

| Document | Audience | What It Covers |
|----------|----------|----------------|
| [User guide](user-guide.md) | End users | Project home, project entry, sessions, chat timeline, file browser, settings, running agent behavior. |
| [Architecture](architecture.md) | Contributors | Flutter UI, app store, session engine, local server, SQLite persistence, workspace bridge, event flow. |
| [Development](development.md) | Contributors | Setup, build, static analysis, tests, native bridge notes, local server debugging. |
| [Release guide](release.md) | Maintainers | Android signing, APK packaging, release assets, release checklist. |
| [AI tools](ai-tools.md) | Power users / integrators | Built-in tools, agent visibility, permission rules, path normalization, tool examples. |
| [Contributing](../CONTRIBUTING.md) | Contributors | Pull request expectations, coding style, review checklist. |
| [Security](../SECURITY.md) | Users / maintainers | Vulnerability reporting and sensitive data handling. |

## What To Keep In Sync

When changing product behavior, update documentation in the same pull request when any of the following changes:

- **Project/session flow**: project home, recent projects, blank landing, session creation/switching/deletion.
- **Agent tools**: new tool IDs, parameter changes, permission behavior, path rules, destructive operations.
- **Workspace files**: browser behavior, supported preview formats, read/write semantics, native bridge behavior.
- **Mobile behavior**: Android floating window, background notifications, notification/overlay permissions, platform limitations.
- **Model/settings behavior**: provider configuration, API key handling, title generation, compaction, cancellation.
- **Security/privacy**: data storage, model API transmission, credentials, signing, local server exposure.

## Style

- Prefer concrete user-visible behavior over implementation trivia in user docs.
- Use exact tool names, file paths, and permission names in developer docs.
- Keep tables short enough to scan; move deeper details into focused docs.
- For every major English user-facing section, maintain a Chinese equivalent.
- For every major Chinese user-facing section, maintain an English equivalent.

## Security

Do not include real API keys, signing passwords, keystore files, private project data, or personal device paths in documentation examples. See [SECURITY.md](../SECURITY.md).

---

## 中文文档

本目录是 **Mag**（`mobile_agent`）的长文档区。根目录 [README](../README.md) 负责项目定位和能力总览；本目录负责用户流程、架构、开发、发布和工具细节。

Mag 文档需要双语维护。凡是影响权限、文件操作、后台运行、移动端行为或用户理解成本的功能，都应尽量同时提供中文和英文说明。

## 文档地图

| 文档 | 读者 | 内容 |
|------|------|------|
| [用户指南](user-guide.md) | 普通用户 | 项目首页、进入项目、会话、消息流、文件浏览器、设置、Agent 运行状态。 |
| [架构说明](architecture.md) | 贡献者 | Flutter UI、状态层、会话引擎、本地服务、SQLite、工作区桥接和事件流。 |
| [开发说明](development.md) | 贡献者 | 环境、构建、静态分析、测试、原生桥接、本地服务调试。 |
| [发布说明](release.md) | 维护者 | Android 签名、APK 打包、Release 资产和发布检查。 |
| [AI 工具](ai-tools.md) | 高级用户 / 集成者 | 内置工具、Agent 可见性、权限规则、路径规范和调用示例。 |
| [贡献指南](../CONTRIBUTING.md) | 贡献者 | PR 期望、代码风格和 Review 关注点。 |
| [安全说明](../SECURITY.md) | 用户 / 维护者 | 漏洞报告和敏感数据处理。 |

## 需要同步更新的内容

当产品行为发生变化时，请在同一个 PR 中同步更新文档，尤其是以下内容：

- **项目/会话流程**：项目首页、最近项目、空白落地页、会话创建/切换/删除。
- **Agent 工具**：新增工具、参数变化、权限策略、路径规则、破坏性操作。
- **工作区文件**：文件浏览器、预览格式、读写语义、原生桥接行为。
- **移动端行为**：Android 小窗、后台通知、通知/悬浮窗权限、平台限制。
- **模型/设置行为**：模型服务商配置、API Key、标题生成、压缩、取消。
- **安全/隐私**：数据存储、模型 API 传输、凭据、签名、本地服务暴露。

## 写作风格

- 用户文档优先描述可感知行为，不堆实现细节。
- 开发文档中准确写出工具名、文件路径、权限名和接口名。
- 表格保持可扫描，细节放到对应专题文档。
- 重要英文用户文档应有中文对应内容。
- 重要中文用户文档应有英文对应内容。

## 安全

文档示例中不要包含真实 API Key、签名密码、keystore、私有项目数据或个人设备路径。安全问题见 [SECURITY.md](../SECURITY.md)。
