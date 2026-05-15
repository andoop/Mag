# Quickstart

This guide gets Mag running locally and helps you complete the first useful agent workflow.

## Requirements

- Flutter and Dart compatible with `pubspec.yaml`.
- Android SDK plus a device or emulator. Android is the primary development target today.
- A model provider API key configured inside the app.
- Optional for iOS work: Xcode and CocoaPods.

## Run Locally

```bash
git clone https://github.com/andoop/Mag.git
cd Mag
flutter pub get
flutter run
```

For a debug APK:

```bash
flutter build apk --debug
```

The debug APK is written under `build/app/outputs/flutter-apk/`.

## First Workspace

1. Open Mag.
2. Create a sandbox project or reopen a recent project.
3. Open Settings and add a model provider/API key.
4. Start a session from the workspace screen.
5. Ask the agent to inspect files, create a document, or make a small code change.
6. Review tool calls and approve sensitive actions.
7. Use Git tools to inspect, stage, commit, or sync when ready.

## Try These Prompts

```text
Summarize this project and create docs/project-summary.docx.
```

```text
Create an XLSX tracker for the remaining release tasks.
```

```text
Build a small HTML page that records audio through MagNative and previews it.
```

```text
Check the Git status and explain the current changes before I commit.
```

## Troubleshooting

- If model calls fail, check provider URL, API key, and selected model.
- If file tools fail, make sure the current project/workspace is open.
- If Android floating window is unavailable, grant "Display over other apps".
- If camera or microphone actions fail, grant camera and microphone permissions.
- If debug APK install fails with `INSTALL_FAILED_TEST_ONLY`, install with `adb install -r -t`.

---

# 快速开始

1. 安装与 `pubspec.yaml` 匹配的 Flutter/Dart。
2. 准备 Android SDK、真机或模拟器。
3. 运行 `flutter pub get && flutter run`。
4. 在应用内创建项目并配置模型服务商。
5. 从一个小任务开始，例如生成 DOCX/XLSX/PPTX、查看 Git 状态或让 Agent 修改一个文件。
