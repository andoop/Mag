# Development

How to build, test, and debug **Mag** as a contributor.

## Prerequisites

- **Flutter** SDK matching `pubspec.yaml` (`environment.sdk`).
- **Android Studio** or Android SDK + emulator/device for the primary target.
- This repo root contains `pubspec.yaml` — run all commands from this directory (the cloned **Mag** repository root).

## Setup

```bash
git clone https://github.com/andoop/Mag.git
cd Mag
flutter pub get
flutter run
```

## Static analysis

```bash
dart analyze lib/
```

Fix all issues before opening a pull request.

## Tests

```bash
flutter test
```

Add tests alongside features when behavior is easy to pin down (parsers, pure logic). UI and engine integration may rely on manual QA on device.

## Native workspace bridge

- Android entry: `android/app/src/main/kotlin/.../MainActivity.kt` (MethodChannel `mobile_agent/workspace`).
- When adding channel methods, update **`WorkspaceBridge`** in Dart and keep error codes (`not_found`, `not_file`, …) consistent.

## Local server debugging

- The app starts an **`HttpServer` on loopback** with a random port; `AppState.serverUri` reflects it.
- Point an external HTTP client at that base URL only for local debugging; routes are not authenticated by design (local-only).

## Logs

- Optional debug flags exist in core files (e.g. `_kDebugServer`, `_kDebugEngine`); keep them **off** in commits unless diagnosing.

## Project layout (reminder)

| Path | Role |
|------|------|
| `lib/app/` | `MaterialApp` entry |
| `lib/ui/` | Screens and `home_page` library parts |
| `lib/store/` | `AppController`, stores |
| `lib/core/` | Engine, DB, server, tools, models |
| `lib/sdk/` | HTTP client |
| `docs/` | This documentation |

---

## 中文开发说明

- 在克隆的 **Mag** 仓库根目录（含 `pubspec.yaml`）执行 `flutter pub get` / `flutter run`。
- 提交前运行 **`dart analyze lib/`**，尽量通过全部检查。
- 原生侧扩展工作区能力时，同步修改 Dart **`WorkspaceBridge`** 与 Kotlin **`MainActivity`** 的 channel 约定。
- 本地 HTTP 服务仅监听回环地址，勿在公网暴露。
