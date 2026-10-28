# Codex Usage Status v0.1.1

本 Fork 的首个可下载版本，基于 [tollenceld/codex-usage-status](https://github.com/tollenceld/codex-usage-status)，保留原项目的 MIT 许可和来源说明。

This is the first downloadable release of this fork, derived from [tollenceld/codex-usage-status](https://github.com/tollenceld/codex-usage-status). The upstream MIT license and attribution are retained.

Each app bundle includes the full MIT license at `CodexUsageStatus.app/Contents/Resources/LICENSE`.

## 下载与安装 / Download and installation

- `CodexUsageStatus-0.1.1-macos-arm64.zip`：Apple Silicon Mac。
- `CodexUsageStatus-0.1.1-macos-x86_64.zip`：Intel Mac。
- `SHA256SUMS.txt`：两个 ZIP 的 SHA-256 校验值。

解压对应 ZIP，将 `CodexUsageStatus.app` 移到“应用程序”目录并打开。应用只显示在菜单栏。将两个 ZIP 与 `SHA256SUMS.txt` 放在同一目录后，可运行 `shasum -a 256 -c SHA256SUMS.txt` 校验文件完整性。

**签名状态：** 下载包仅经过临时签名，没有 Developer ID 签名，也没有经过 Apple 公证；macOS Gatekeeper 可能阻止打开。也可以选择[从源码构建](https://github.com/Serendipity-Y/codex-usage-status#quick-start-from-source)。

**Signing:** These apps are ad-hoc signed; they do not have a Developer ID signature and have not been notarized by Apple. macOS Gatekeeper may block a downloaded app. You can also [build from source](https://github.com/Serendipity-Y/codex-usage-status#quick-start-from-source).

## 本次更新 / Changes

- 显示 5 小时和每周剩余额度；悬浮卡片显示可用重置次数、额度恢复时间和下次数据刷新时间。
- 修复初始化时序和输出阻塞导致的潜在刷新失败；失败后按 60、120、300 秒间隔重试。
- 失败时保留上次记录，显示错误类型与上次成功时间；修复状态切换时悬浮卡片内容被裁切。
- 额度通过本地 Codex app-server 读取；应用不直接读取凭据，也不向项目维护者上传遥测数据。

The menu-bar app shows 5-hour and weekly usage with reset and refresh details. This release improves initialization and output handling, adds failure backoff and clearer stale-data indicators, and fixes hover-card clipping.

ChatGPT 自动启停助手**不包含在应用 ZIP 中**，需要下载源码，并使用 Python 3 和 Xcode Command Line Tools 安装。参见[设置说明](https://github.com/Serendipity-Y/codex-usage-status#optional-chatgpt-startquit-behavior)。

The optional ChatGPT start/quit helper is **not included in the app ZIP**. It requires the source repository, Python 3, and Xcode Command Line Tools. See [setup instructions](https://github.com/Serendipity-Y/codex-usage-status#optional-chatgpt-startquit-behavior).

See the [changelog](https://github.com/Serendipity-Y/codex-usage-status/blob/main/CHANGELOG.md) for details and known refresh behavior.
