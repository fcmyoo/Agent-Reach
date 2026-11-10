# Agent-Reach 新渠道开发规范

> 本文档是给 Codex / 后续开发者的落地规范，基于现有 15 个渠道的代码结构和项目原则提炼。
> 上游项目地址：https://github.com/fcmyoo/Agent-Reach

---

## 1. 项目定位（不变原则）

Agent Reach 是 **"互联网能力路由器"**，不是 wrapper。

- **只做路由和调用**，不重新发明轮子。
- **换接入方式 = 调整 backends 列表顺序**，不是重写代码。
- **绝不修改上游开源项目源代码**（yt-dlp、twitter-cli、bilibili-cli 等）。
- 渠道失效时，只需在 backends 列表里把下一个可用的后端挪到第一位。

---

## 2. 渠道文件结构

每个渠道是一个独立文件，放在 `agent_reach/channels/` 目录下：

```
agent_reach/channels/
├── __init__.py          # 注册入口（ALL_CHANNELS 列表）
├── base.py              # Channel 抽象基类（不可修改接口）
├── v2ex.py              # 零配置公开 API 型（参考）
├── xueqiu.py            # 需登录 Cookie 型（参考）
├── twitter.py           # 多后端路由型（参考）
├── youtube.py           # OpenCLI 适配器型（参考）
└── <new_platform>.py    # ← 新增的渠道文件
```

---

## 3. Channel 接口契约（必须遵守）

继承 `agent_reach.channels.base.Channel`，必须实现/遵守：

```python
from .base import Channel

class NewChannel(Channel):
    # === 类属性 ===
    name: str = "new_platform"                    # 唯一标识，蛇形命名
    description: str = "新平台中文描述"            # 中文名，用于 doctor 输出
    backends: List[str] = ["后端A", "后端B"]       # 有序候选列表，[0] = 首选
    tier: int = 0                                 # 0=零配置, 1=需免费key, 2=需配置

    # === 必须实现 ===
    def can_handle(self, url: str) -> bool:
        """判断 URL 是否属于本平台。用 host_matches 或自定义逻辑。"""
        ...

    def check(self, config=None) -> Tuple[str, str]:
        """探测后端可用性，返回 (status, message)。
        status: 'ok' | 'warn' | 'off' | 'error'
        必须设置 self.active_backend。
        """
        ...

    # === 可选实现（数据获取方法）===
    def search(self, query: str, limit: int = 10) -> list:
        """搜索，返回标准化 list[dict]。"""
        ...

    def read(self, url: str) -> dict:
        """读取单条内容，返回标准化 dict。"""
        ...
```

### `check()` 的两段式优先级规则（来自 twitter.py 注释）

1. **先收集全部候选状态**（每个 backend 独立探测）。
2. **第一个 `ok` 获胜**——没有 `ok` 才轮到第一个 `warn`。
3. 否则（只剩 error/timeout）返回 `error`。
4. 没有可用候选时返回 `warn` + 安装提示。

> 反直觉但关键：「装了但未登录」的 backend（`warn`）不能挡在「完整可用」的 backend（`ok`）前面。

---

## 4. 三种渠道类型及模板

### 类型 A：零配置公开 API（如 V2EX、GitHub）

- `tier = 0`
- 直接用 `urllib` / `requests` 调用公开 HTTPS API
- 需要 URL 白名单校验（防止 SSRF）
- `check()` 发一个轻量请求验证连通性
- 参考：`agent_reach/channels/v2ex.py`

### 类型 B：需登录 Cookie（如 雪球、LinkedIn）

- `tier = 1` 或 `2`
- 支持两种认证方式：
  1. **OpenCLI 浏览器登录态**（桌面首选）：Chrome 打开且登录目标网站，OpenCLI 自动复用
  2. **Cookie-Editor 导出**：用户手工导出 cookie → `agent-reach configure --from-browser chrome --platform <name>`
- `check()` 先探测 OpenCLI，再探测 cookie 文件
- 参考：`agent_reach/channels/xueqiu.py`、`agent_reach/channels/twitter.py`

### 类型 C：纯 OpenCLI 适配器（如 B站、小红书、Twitter）

- 本渠道文件只负责 **URL 路由 + doctor 状态检查**
- 实际数据获取由 `~/.opencli/clis/<platform>/` 下的适配器完成
- `check()` 调用 `agent_reach.backends.opencli_status()` 探测
- 参考：`agent_reach/channels/bilibili.py`、`agent_reach/channels/facebook.py`

---

## 5. 注册流程（6 步）

### Step 1：创建渠道文件

在 `agent_reach/channels/` 下新建 `<platform>.py`，实现接口契约。

### Step 2：注册到 channels/__init__.py

在 `ALL_CHANNELS` 列表里添加实例：

```python
from .new_platform import NewChannel

ALL_CHANNELS: List[Channel] = [
    # ... 现有渠道 ...
    NewChannel(),          # ← 新增
]
```

### Step 3：（可选）注册 install 命令

如果渠道需要安装依赖（CLI 工具、npm 包等），在 `cli.py` 的 `CHANNEL_INSTALLERS` 字典里添加：

```python
CHANNEL_INSTALLERS = {
    # ... 现有 ...
    "new_platform": _install_new_platform_deps,
}
```

同时实现 `_install_new_platform_deps()` 函数。

### Step 4：写测试

在 `tests/` 下新建 `test_new_platform_channel.py`，必须覆盖：

- `test_channel_registry_contract`（自动覆盖：name 唯一、description 非空、backends 是 list、tier 合法）
- `test_channel_check_contract_with_minimal_runtime`（自动覆盖：check() 返回合法 status + message）
- `test_new_platform_specific`（渠道特有逻辑，如 can_handle URL、search 返回结构）

运行测试：
```bash
cd D:/code/github/Agent-Reach
pytest tests/test_new_platform_channel.py -v
```

### Step 5：更新 SKILL.md 路由表

编辑 `agent_reach/skill/SKILL.md`：

1. 在 `description` 的 platform 列表里加入新平台关键词
2. 在路由表里加一行：
   ```markdown
   | 新平台搜索/内容 | category | [references/category.md](references/category.md) |
   ```
3. 如果 category 是新的，需要新建 `references/<category>.md`

### Step 6：更新 references 分类文档

在对应的 `references/<category>.md` 里加入新平台的使用文档：

- 零配置命令（如果有）
- 需登录的后端及配置方式
- 重试链（如果有多后端）
- 安全/频率限制注意

---

## 6. 安全规范（强制）

1. **SSRF 防护**：所有外部请求必须校验 URL hostname，只允许访问目标平台域名。
   - 参考 `v2ex.py` 的 `_validate_api_url()`
   - 禁止用户输入直接拼接到 URL 做请求
2. **凭据不泄露**：
   - Cookie/Token 只存于 `~/.agent-reach/` 或 `config.yaml`
   - 日志里自动脱敏（用 `scrub_url_credentials`）
   - `doctor` 不执行会写 device-id 的命令（如 `gh auth status`）
3. **不替用户登录**：
   - 不得自动打开浏览器执行登录
   - 不得读取浏览器 Cookie 数据库（DPAPI 限制）
   - OpenCLI `login` 命令只用于"等待用户完成浏览器登录"，不做自动填充

---

## 7. 测试验收标准

```bash
# 全量测试（必须全绿）
cd D:/code/github/Agent-Reach
pytest tests/ -v

# 渠道契约测试（自动覆盖所有渠道）
pytest tests/test_channel_contracts.py -v

# 渠道专项测试
pytest tests/test_new_platform_channel.py -v

# doctor 输出验证
python -m agent_reach.cli doctor
python -m agent_reach.cli doctor --json
```

---

## 8. 输出交付物清单

每个新渠道开发完成后，必须交付：

| 文件 | 说明 |
|------|------|
| `agent_reach/channels/<platform>.py` | 渠道实现 |
| `agent_reach/channels/__init__.py` | 注册（已改） |
| `tests/test_<platform>_channel.py` | 专项测试 |
| `agent_reach/skill/SKILL.md` | 路由表已更新 |
| `agent_reach/skill/references/<cat>.md` | 使用文档 |
| `cli.py`（如需要） | install 命令已注册 |

---

## 9. 快速决策树（选哪种类型）

```
目标平台有公开 API 且无需登录？
├─ 是 → 类型 A（零配置公开 API）
└─ 否 → 平台有成熟的第三方 CLI 工具？
    ├─ 是 → 类型 C（纯 OpenCLI 适配器，让 OpenCLI 社区维护适配器）
    └─ 否 → 类型 B（需登录 Cookie，支持 OpenCLI + Cookie-Editor 双路径）
```

> **优先选类型 C**（OpenCLI 适配器）：维护成本最低，适配器由 OpenCLI 社区维护，Agent-Reach 只负责 URL 路由和 doctor 状态检查。

---

## 10. 现有渠道参考索引

| 渠道 | 类型 | 参考文件 |
|------|------|---------|
| V2EX | A（零配置 API） | `channels/v2ex.py` |
| GitHub | A（零配置 CLI） | `channels/github.py` |
| 雪球 | B（Cookie 登录） | `channels/xueqiu.py` |
| Twitter | B（多后端路由） | `channels/twitter.py` |
| B站 | C（OpenCLI） | `channels/bilibili.py` |
| 小红书 | C（OpenCLI） | `channels/xiaohongshu.py` |
| YouTube | C（OpenCLI） | `channels/youtube.py` |
