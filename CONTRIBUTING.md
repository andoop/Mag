# Contributing

Thanks for helping improve Mag. This project values focused changes, clear behavior, and documentation that matches the product.

## Good First Contributions

- Fix documentation gaps.
- Add tests for existing tools.
- Improve error messages.
- Polish mobile UI states.
- Add small, well-scoped native bridge improvements.

## Development Loop

```bash
flutter pub get
dart analyze lib test
flutter test
flutter run
```

## Pull Request Checklist

- Keep the change focused.
- Explain the user-facing behavior.
- Include tests for tool/runtime behavior when practical.
- Update docs for new features, permissions, tools, or supported formats.
- Do not commit secrets, keystores, API keys, `android/key.properties`, or private workspace data.

## Documentation Expectations

If a change affects users, contributors, tool behavior, permissions, file formats, Git operations, native capabilities, or release behavior, update the relevant document under `docs/`.

Start with [docs/README.md](docs/README.md).

## Review Priorities

Reviewers should prioritize:

- User safety and permission clarity.
- Data privacy and secret handling.
- Workspace path correctness.
- Cross-platform behavior.
- Tests and documentation.
