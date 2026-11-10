# Windows 平台接入注意事项

> 本文件是本机（Windows）实测补充，不属于上游 Agent Reach 通用文档。
> 渠道与动作名按 Agent Reach 1.6 的 `agent-reach channels` 输出对齐。

## DPAPI / Chrome App-Bound Encryption 限制

- Chrome 2024-07 起启用 App-Bound Encryption，Windows 上无法通过常规方式提取 Chrome cookies 文件
- `yt-dlp --cookies-from-browser chrome` 会报 `Failed to decrypt with DPAPI`（yt-dlp/yt-dlp#10927）
- 关闭 Chrome 无法修复；这是 Chrome 安全机制，不是 yt-dlp bug
- Firefox 在 Windows 上也可能遇到类似限制（取决于版本）

**正确做法**：优先使用 OpenCLI 适配器（浏览器扩展直接读登录态，绕开 cookies 文件）。

## 已验证的 Windows 稳定方案

Agent Reach 1.6 走 `agent-reach <渠道> <动作>` 统一入口，底层仍由 OpenCLI 适配器承担。

| 平台 | Agent Reach 动作 | 底层 | 说明 |
|------|------------------|------|------|
| YouTube | `youtube read/search/subtitle/transcribe` | `opencli youtube` | search/video/transcript/comments 全通 |
| B站 | `bilibili search/read/hot/subtitle` | `bili` + `opencli bilibili subtitle` | bili-cli 零配置搜索；OpenCLI 读字幕 |
| Twitter/X | `twitter search/profile/tweets/thread` | `opencli twitter` | 需 Chrome 登录 x.com |
| 小红书 | `xiaohongshu search/read/comments` | `opencli xiaohongshu` | 需 Chrome 登录 xiaohongshu.com；OpenCLI 2.0 返回格式已在 1.6.1 适配 |
| Reddit | `reddit search/read/subreddit` | `opencli reddit` | 需 Chrome 登录 reddit.com |
| Facebook | `facebook search/profile` | `opencli facebook` | 需 Chrome 登录 facebook.com |
| Instagram | `instagram search/profile/posts` | `opencli instagram` | 需 Chrome 登录 instagram.com |
| 雪球 | `xueqiu search/read` | `opencli xueqiu` | 需 Chrome 登录 xueqiu.com |
| LinkedIn / BOSS直聘 | `linkedin ...` / `boss ...` | `opencli linkedin` / `opencli boss` | 需 Chrome 登录；LinkedIn 职位解析依赖 OpenCLI 2.0.3 |
| V2EX | `v2ex ...` | 公开 API（curl） | 零配置，无需登录 |
| GitHub | `github search/read` | `gh` CLI | 已认证即可用 |
| 任意网页 | `web read` | `curl https://r.jina.ai/URL` | 零配置 |

## Windows 端口占用

专用浏览器默认用 9222，被别的程序占用时**不要**去关那个程序，改端口：

```bash
agent-reach configure browser-port <空闲端口>
```

## PATH 注意事项

- Python `pip install --user` 默认装到 `%APPDATA%\Python\Python311\Scripts\`
- 该目录**不在用户 PATH 中**，需手动添加才能全局访问
- 添加方式：`[Environment]::SetEnvironmentVariable('Path', ..., 'User')`（持久化）
- 验证：`command -v <tool>` 或重新开 shell
- 1.6 起官方安装方式改为 `uv tool install`，装的命令落在 uv 的 tool 目录；用 `uv tool update-shell` 把该目录写进 PATH

## OpenCLI 扩展（Windows）

- 扩展以 unpacked 方式加载，源码在 OpenCLI clone 的 `extension/` 目录
- 升级 OpenCLI 后扩展版本可能落后，用 `opencli doctor` 看 `latestExtensionVersion` 与 `extensionOutdated`
- 扩展未连接时先确认 Chrome 是否在运行（`tasklist | findstr chrome`），再 `opencli daemon restart`
- daemon 与扩展的 loopback 地址要一致；2.0.3 修了 daemon/CLI/扩展地址协商不一致的问题

## 飞书 user-token 过期

- `lark-cli auth status` 中 `user` 身份会显示 `refresh_token expired`
- bot 身份不受影响，仍可正常使用
- user 身份过期后需重新 `lark-cli auth login --recommend`
- 判断依据：`"identities": {"user": {"status": "missing"}}`
