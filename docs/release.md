# Release guide

How to prepare a signed Android APK and publish it as a GitHub Release asset.

## Recommended distribution flow

1. Build a signed APK locally with your release keystore.
2. Create a GitHub Release such as `v1.0.0`.
3. Upload the APK as a release asset.
4. Add short English and Chinese release notes.
5. Link users to the Release page from `README.md`.

Avoid committing APK files directly into the repository history.

## Signed APK checklist

- `android/key.properties` exists locally and is not committed.
- `storeFile` points to a valid `*.jks` or `*.keystore`.
- `flutter build apk --release` succeeds.
- Verify the app installs on a real Android device before publishing.

## Release notes template

### English

```md
## Highlights

- First public Android APK release for Mag.
- On-device mobile AI coding workflow with sessions, file tools, and workspace-aware operations.
- Local loopback server for debugging and integration.

## Notes

- This release is currently focused on Android.
- Configure your model provider and API key in Settings after installation.
- Please report bugs through GitHub Issues and sensitive problems through the private channel described in SECURITY.md.
```

### 中文

```md
## 亮点

- Mag 首个公开 Android APK 版本。
- 提供移动端 AI 编程工作流，支持会话、文件工具和工作区感知操作。
- 内置本地回环服务，便于调试和集成。

## 说明

- 当前版本主要面向 Android。
- 安装后请在应用的“设置”中配置模型服务商与 API Key。
- 普通问题欢迎通过 GitHub Issues 反馈，安全问题请按 SECURITY.md 中的方式私下报告。
```
