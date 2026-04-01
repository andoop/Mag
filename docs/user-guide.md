# User guide

How to use **Mag** on your device. This complements in-app UI labels (Chinese / English).

## First launch

1. Open the app and grant **storage / file access** when prompted (required to pick a workspace folder on Android).
2. From the **project home**, open an existing recent workspace or tap to **add a project** (folder picker).
3. You land on the **chat** screen for that workspace.

## Project home

- **Recent workspaces** — Quick reopen folders you used before (stored locally).
- **Open project** — Pick a directory; Mag treats it as the **workspace root** for tools and previews.

## Chat screen (workspace)

### Top bar

| Control | Action |
|---------|--------|
| Back | Return to **project home** (workspace session is left; data stays on device). |
| Title | Current session title (or “New session” on the blank landing page). |
| Folder | **Workspace file browser** — browse folders, open files (Markdown/HTML preview vs source, PDF, images, code). |
| Settings | Model provider, API keys, and related options. |
| Chat bubble | **Session drawer** — history, new session, compact, project memory, rename/delete sessions. |

### New session landing

When no session is active, the composer explains that **the first message creates a session**. You can also use the drawer to **create a session immediately** or return to the **blank landing** page.

### Sessions

- **Default titles** follow an OpenCode-style pattern (`New session - <UTC ISO>`). After the **first real user message**, the app may **auto-generate a short title** via the model (only for main sessions, not child/subtask titles).
- **Rename / delete** — Use the ⋮ menu on a session row in the drawer. Deleting the active session returns you to the blank landing state.

### File browser

- Navigate with folder rows; **Parent folder** goes up one level.
- **Refresh** reloads the directory from the device.
- **Files** open in the appropriate viewer (see README feature list).

### While the agent runs

- **Stop / cancel** follows the session lifecycle (busy state in the title area).
- **Permissions** — Some tools ask for allow/deny/always; replies are tied to the workspace.

---

## 中文用户指南

### 首次使用

1. 打开应用并按提示授予**存储/文件访问**权限（在 Android 上用于选择工作区目录）。
2. 在**项目首页**打开最近项目，或**添加项目**（文件夹选择器）。
3. 进入该工作区的**对话页**。

### 项目首页

- **最近工作区** — 快速打开用过的文件夹（仅本机保存）。
- **打开项目** — 选定目录作为**工作区根路径**，供工具与预览使用。

### 对话页顶栏

| 控件 | 作用 |
|------|------|
| 返回 | 回到**项目首页**（离开当前工作区界面，数据仍保留在本机）。 |
| 标题 | 当前会话标题（空白落地页时为「新建会话」等）。 |
| 文件夹 | **工作区文件** — 浏览目录；支持 Markdown/HTML（排版/源码）、PDF、图片、代码高亮等。 |
| 设置 | 模型服务商、API Key 等。 |
| 会话图标 | **会话抽屉** — 历史、新建、压缩、项目记忆、重命名/删除会话。 |

### 会话与标题

- 默认标题为 OpenCode 风格；**首条用户消息**后，主会话可能由模型**自动生成短标题**（子会话不自动改标题）。
- 在抽屉列表 ⋮ 中可**重命名 / 删除**；删除当前会话会回到**空白落地页**。

### 文件浏览器

- 点击文件夹进入；**上级目录**返回上一层。
- **刷新**强制重新读取目录。
- 不同类型文件会进入对应预览（见主 README）。
