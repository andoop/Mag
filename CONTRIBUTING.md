# Contributing to Mag

Thank you for helping improve **Mag** (`mobile_agent`). This document explains how we like to receive contributions.

## Ways to contribute

- **Bug reports** — Open an issue with steps to reproduce, expected vs actual behavior, device/OS, and Flutter version when relevant.
- **Feature ideas** — Open an issue for discussion before large refactors.
- **Pull requests** — Keep each PR focused on one concern; link the issue when applicable.

## Before you send a PR

1. **Analyze** — `dart analyze lib/` passes with no issues.
2. **Tests** — Run `flutter test` if your change touches testable logic.
3. **Style** — Match surrounding code (naming, imports, formatting). Avoid unrelated renames or drive-by refactors.
4. **Commits** — Clear messages in English (or bilingual body if you prefer); describe *what* and *why*.
5. **Docs** — Update `README.md` or `docs/` if behavior or setup changes.

## Review expectations

Maintainers may request changes. Small follow-up commits or a single amended commit are both fine unless asked otherwise.

## Internationalization

User-visible strings should go through the existing `l(context, zh, en)` pattern where the file already uses it.

## License

By contributing, you agree your contributions are licensed under the same **MIT License** as the project (see [LICENSE](LICENSE)).

---

## 中文

感谢参与 **Mag** 的贡献。提交 PR 前请确保 **`dart analyze lib/`** 无问题，尽量运行 **`flutter test`**，保持改动单一职责、与周边代码风格一致。用户可见文案请沿用现有的 **`l(context, 中文, English)`** 形式。贡献内容将按与本项目相同的 **MIT 许可证** 授权。
