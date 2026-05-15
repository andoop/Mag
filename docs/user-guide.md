# User Guide

This guide explains Mag from the user's point of view: create a workspace, talk to the agent, approve tools, generate artifacts, and keep work moving on mobile.

## Demo

[Watch the Mag app demo video](assets/mag-app-demo.mp4)

## Projects

Mag starts from projects. A project owns its workspace files, sessions, permissions, and local state.

<p align="center">
  <img src="assets/home.jpg" alt="Mag project home" width="260" />
</p>

- Use **New project** to create a sandbox workspace.
- Use **Recent projects** to reopen local work.
- Rename or delete local project entries from the project list menu.
- Tool paths are workspace-relative, not raw device paths.

## Sessions

Sessions are conversations tied to a project.

<p align="center">
  <img src="assets/session-timeline.jpg" alt="Agent session timeline" width="260" />
</p>

- The first real user message creates a working session.
- The session drawer lets you create, switch, rename, delete, compact, or use project memory actions where available.
- Long-running work can be stopped or cancelled from the busy state.
- Titles may be generated automatically after the first user message.

## Composer And Attachments

The composer is where text, workspace context, and device context meet.

- Type prompts naturally.
- Use `@` to reference workspace files.
- Attach workspace files or device files.
- Capture a photo inside the app.
- Record audio inside the app.
- Record video inside the app.
- Ask the agent to generate DOCX, XLSX, or PPTX files.

Generated media and Office files are returned as attachments so you can preview, share, or continue working with them.

## File Browser And Previews

The file browser lets you inspect the workspace without leaving the agent flow.

<p align="center">
  <img src="assets/workspace-files.jpg" alt="Workspace file actions" width="260" />
</p>

Supported preview surfaces include:

- Markdown and HTML.
- PDF.
- Images.
- Text and code.
- Office attachments where supported.

## Git Workflow

Mag treats Git as part of the mobile workflow.

<p align="center">
  <img src="assets/git-workflow.jpg" alt="Git workflow in Mag" width="260" />
</p>

You can ask the agent or use Git surfaces to:

- Inspect status, diffs, and history.
- Stage and unstage paths.
- Commit or amend.
- Manage branches.
- Restore, reset, merge, rebase, and cherry-pick.
- Manage remotes, fetch, pull, and push.
- Configure identity, SSH keys, and credentials.

## Models And Providers

Open Settings to configure model providers.

- Add API keys.
- Use provider/model discovery where supported.
- Select recent models.
- View context usage where available.
- Use custom OpenAI-compatible endpoints for gateways, proxies, local, or self-hosted services.

## Permissions

Mag asks before sensitive actions so users can stay in control.

| Permission | Why It Exists |
|------------|---------------|
| File/project access | Read, preview, edit, and generate workspace files. |
| Tool permissions | Approve edits, downloads, web access, environment file access, and destructive actions. |
| Camera and microphone | Capture photos, record audio, and record video inside the app. |
| Notifications | Show background running state and Android foreground service status. |
| Display over other apps | Enable Android floating window. |

## Mobile Mini-Window

The mobile mini-window lets you keep watching an active session while using other apps.

- Android uses a system overlay and foreground service.
- Android supports mini, line, and full display modes.
- The full mode can show status, assistant content, Markdown tables, reasoning text, and tool summaries.
- iOS uses a Picture-in-Picture style foundation where supported.

---

# 用户指南

Mag 的基本使用路径是：创建项目，配置模型，开始会话，审批工具，查看文件/Git 结果，必要时通过小窗继续观察任务。

常用入口：

- 项目首页：新建或打开最近项目。
- 会话抽屉：新建、切换、重命名、删除、压缩会话。
- 输入区：输入 prompt、`@` 引用文件、附加文件、拍照、录音、录像。
- 文件浏览器：预览 Markdown、HTML、PDF、图片、文本、代码和 Office 附件。
- Git：查看 diff/status/log，暂存、提交、分支和同步。
- 设置：配置模型、API Key、Git identity、SSH key 和凭据。

你可以让 Agent 生成 DOCX、XLSX、PPTX，也可以让 AI 生成的网页通过 MagNative 调用原生拍照、录音和录像能力。
