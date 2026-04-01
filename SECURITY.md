# Security policy

## Supported versions

Security fixes are applied to the **default branch** (`main`) of this repository. There are no separate LTS branches at this time.

## Reporting a vulnerability

**Please do not** open a public GitHub issue for undisclosed security vulnerabilities.

Instead, contact the maintainers **privately** (e.g. via GitHub Security Advisories for the repository, or email if listed in the maintainer profile). Include:

- A short description of the issue and its impact
- Steps to reproduce (or a proof-of-concept) if safe to share
- Affected platform (e.g. Android) and app/build context if relevant

We aim to acknowledge reasonable reports within a few days; timelines depend on maintainer availability.

## Scope notes

- The in-app **local HTTP server** is intended to bind **loopback only**; treating it as a remote attack surface is generally out of scope unless you show a practical escalation from another component.
- **API keys** and workspace data are under the user’s control; guidance is documented in the [README](README.md) (security & privacy).

---

## 中文（摘要）

请勿在公开 Issue 中披露未修复的安全问题。请通过 **GitHub Security Advisories** 或维护者私下提供的渠道报告，并附影响说明与复现步骤（如可安全提供）。应用内本地 HTTP 服务设计为仅监听回环地址；API 密钥与工作区数据由用户自行保管，详见 [README](README.md)。
