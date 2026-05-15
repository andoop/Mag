# Release

This checklist is for maintainers preparing a Mag release.

## Before Building

- Confirm version and build number.
- Run formatting, analysis, and tests.
- Verify no secrets are present.
- Update README and docs for user-visible changes.
- Check demo video, screenshots, and release notes.

## Android Debug Build

```bash
flutter build apk --debug
```

Debug APKs are local development artifacts and should not be committed.

## Android Release Build

Release signing depends on local key configuration. Do not commit keystores, passwords, or `android/key.properties`.

```bash
flutter build apk --release
```

## Release Notes

Each release should include:

- Highlights.
- New features.
- Fixes.
- Breaking changes or migration notes.
- Known limitations.
- Download links.

## Publishing

Use GitHub Releases for signed artifacts. Keep binary artifacts out of normal git history unless there is a deliberate project policy.

---

# 发布

发布前至少确认：测试通过、文档同步、没有密钥、签名配置未提交、Release Notes 写清楚新增功能和已知限制。
