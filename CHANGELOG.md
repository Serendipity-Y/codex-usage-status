# 更新记录 / Changelog

## 未发布 / Unreleased — 2026-10-27

### 中文

- 改善额度刷新稳定性：等待 Codex app-server 初始化完成后再请求额度，并处理进程提前退出、输出阻塞和分段数据。
- 自动重试：首次失败后等待 60 秒，连续失败后依次等待 120 秒和 300 秒；成功后恢复正常刷新间隔。
- 改善失败提示：悬浮卡片保留上次成功的数据，并显示错误类型与上次成功时间；状态栏继续用问号表示当前数据未更新。
- 修复悬浮卡片在正常、失败和恢复状态间切换时，窗口高度不同步导致内容被裁切的问题。
- 增加本机诊断记录，仅记录固定错误类别、RPC 错误码和重试时间；不记录原始服务端输出、凭据或额度数值。
- 增加针对初始化延迟、错误输出阻塞、进程退出、超时、数据分段以及卡片尺寸切换的回归测试。

### English

- Improve refresh reliability by waiting for app-server initialization before requesting usage and handling early exits, blocked output, and split data.
- Retry failed refreshes after 60, 120, then 300 seconds; a successful refresh restores the normal interval.
- Keep the last successful snapshot in the hover card, with the failure category and last-success time. Question marks continue to indicate that the status-bar data is stale.
- Fix hover-card clipping when switching between normal, failed, and recovered states.
- Add local diagnostics containing fixed error categories, RPC error codes, and retry timing, without raw server output, credentials, or usage values.
- Add regression coverage for delayed initialization, blocked stderr, process exits, timeouts, split data, and popover resizing.

These changes are available from source. This entry does not announce a published binary release.
