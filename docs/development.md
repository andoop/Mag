# Development

This guide is for contributors working on Mag locally.

## Setup

```bash
flutter pub get
flutter run
```

Use Android for the fastest development loop. Use iOS when changing iOS-specific bridges or permissions.

## Common Commands

```bash
dart format lib test
dart analyze lib test
flutter test
flutter build apk --debug
```

## Project Areas

| Path | Purpose |
|------|---------|
| `lib/ui/` | Flutter screens, composer, timeline, previews, settings. |
| `lib/core/` | Session engine, tools, model routing, local runtime. |
| `lib/platform/` | Dart platform bridge interfaces. |
| `android/` | Android native bridges, permissions, floating window, notifications. |
| `ios/` | iOS native bridges and app delegate integrations. |
| `test/` | Tool/runtime tests and behavior coverage. |
| `docs/` | User, contributor, and maintainer documentation. |

## Adding A Tool

1. Define the tool in the registry.
2. Add parameter schema and clear descriptions.
3. Enforce workspace-relative paths.
4. Add permission behavior for sensitive actions.
5. Add tests.
6. Update [AI Tools](ai-tools.md) and feature docs.

## Adding A Native Capability

1. Add the Dart bridge method.
2. Register the capability metadata where applicable.
3. Implement Android and iOS behavior.
4. Handle runtime permissions.
5. Add user-facing UI and cancellation states.
6. Expose it to `window.MagNative` if generated HTML should use it.
7. Update [AI Web Runtime](web-runtime.md).

## Documentation Rule

If a user can see it, approve it, call it, configure it, or rely on it, document it in the same change.

---

# 开发说明

贡献代码前建议先运行：

```bash
dart analyze lib test
flutter test
```

新增工具、端上能力、权限行为、文件格式支持或小窗行为时，必须同步更新 `docs/`。
