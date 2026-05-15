# Mag Documentation

Welcome to the Mag documentation. This folder is organized by audience, not by implementation history.

## Start Here

| Document | Audience | Use It For |
|----------|----------|------------|
| [Quickstart](quickstart.md) | New users / contributors | Run the app, configure a model, and create the first workspace. |
| [Features](features.md) | Users / evaluators | Understand what Mag can do today. |
| [User Guide](user-guide.md) | End users | Learn the product flows after installation. |
| [Document Generation](document-generation.md) | Users / builders | Generate DOCX, XLSX, and PPTX files with the agent. |
| [AI Web Runtime](web-runtime.md) | App builders | Let generated HTML pages call native file/media capabilities. |
| [AI Tools](ai-tools.md) | Power users / integrators | Understand tool IDs, permissions, path rules, and outputs. |
| [Architecture](architecture.md) | Contributors | Understand runtime layers, native bridges, persistence, and events. |
| [Development](development.md) | Contributors | Set up, test, debug, and work on native bridges. |
| [Release](release.md) | Maintainers | Build signed artifacts and publish releases. |
| [Materials Needed](materials-needed.md) | Maintainers / designers | Track screenshots, demo videos, diagrams, and launch assets still needed. |

## Documentation Principles

- Keep the root README short and high-signal.
- Put detailed behavior in focused pages under `docs/`.
- Prefer current product behavior over future promises.
- Mark missing assets clearly instead of pretending they exist.
- Update docs in the same pull request as user-facing behavior changes.
- Keep English as the primary structure and include Chinese sections where they help users onboard.

## What Must Stay In Sync

- New tools or changed tool parameters.
- Supported file preview or generation formats.
- Native capabilities such as camera, microphone, video, save, and share.
- Model provider behavior, permissions, and credential handling.
- Git operations, workspace path rules, and destructive actions.
- Background execution, notifications, floating window, and platform permissions.

---

# Mag 文档

本目录按读者组织，而不是按历史实现组织。根目录 `README.md` 负责项目门面；`docs/` 负责把用户、贡献者、集成者需要的信息讲清楚。

建议阅读顺序：

1. [Quickstart](quickstart.md)：跑起来。
2. [Features](features.md)：看完整能力地图。
3. [User Guide](user-guide.md)：了解产品怎么用。
4. [Development](development.md)：开始贡献代码。
5. [Materials Needed](materials-needed.md)：补齐截图、视频和品牌素材。
