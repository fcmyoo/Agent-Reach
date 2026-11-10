# Agent Reach 测试指南

本文档描述 Agent Reach 的两条测试路径、`test.sh` 的演进历史、各平台运行方式，以及常见问题排查。

---

## 1. 项目测试体系总览

项目有两条互补的测试路径：

| 路径 | 命令 | 验证什么 | 速度 | 网络依赖 |
|---|---|---|---|---|
| **单元测试套件** | `uv run --extra dev pytest tests/ -v` | CLI 路由、配置、doctor、channel 契约等代码逻辑 | 秒级 | 不需要 |
| **一键冒烟测试** | `bash test.sh` | 端到端：干净 venv → 安装 → `install --env=auto` → `doctor` → 14 项 CLI 探测 | 分钟级 | pip 安装依赖需要；`check-update` 一项可 SKIP |

### 1.1 单元测试套件（pytest）

`tests/` 下约 20 个测试文件，覆盖 CLI 入口（`test_cli.py`）、核心路由（`test_core.py`）、配置（`test_config.py`）、诊断引擎（`test_doctor.py`）、channel 契约（`test_channel_contracts.py`）以及各平台 channel（twitter / reddit / youtube / web / v2ex / xueqiu 等）、transcribe、xhs 格式化等。

```bash
# 推荐：uv（自动解析 pyproject.toml 并安装 dev extra：pytest/ruff/mypy）
uv run --extra dev pytest tests/ -v

# 或传统方式
pip install -e ".[dev]"
pytest tests/ -v

# 只跑 CLI 测试
pytest tests/test_cli.py -v
```

**约定（见 CLAUDE.md）：提交前必须 `pytest tests/ -v` 全绿。** 修改 channel / CLI / 配置逻辑时以此为准。

### 1.2 一键冒烟测试（test.sh）

`test.sh` 模拟"一台干净的机器上从零安装 Agent Reach"的完整链路，全程在临时目录的隔离 venv 中进行，任何退出路径都会通过 `trap` 清理：

1. **探测 Python**：依次尝试 `python3` → `python` → `py -3`，要求可实际启动且 ≥ 3.10（Windows Store 的 `python3` 空壳别名会被跳过）。
2. **创建并激活 venv**：同时识别 POSIX 的 `venv/bin/activate` 和 Windows 的 `venv/Scripts/activate` 布局。
3. **安装**：默认安装**脚本所在仓库的工作树**（`SCRIPT_DIR`），用 venv 内的 Python 执行 `-m pip install`；要验证远端包时显式传 `AGENT_REACH_TEST_SOURCE='https://github.com/fcmyoo/Agent-Reach/archive/main.zip'`。
4. **自动配置**：`agent-reach install --env=auto`。
5. **诊断**：`agent-reach doctor`。
6. **14 项 CLI 功能探测**：详见 §2.3。

判定逻辑由 `test_it` 函数承担：`test_it <名称> <命令> [期望正则] [SKIP 正则]`。输出命中期望正则记 ✅ PASS；命中环境缺失/网络不可用关键词（未安装、未配置、`[!]`、`[X]`、无法检查更新、timeout、DNS 等）记 ⏭️ SKIP；否则 ❌ FAIL。`FAIL > 0` 时脚本以退出码 1 结束。

---

## 2. test.sh 演进历史

`test.sh` 经历了三轮修复，方案文档均保存在 `docs/plans/`：

| # | 方案文档 | 解决的问题 | 关键改动 |
|---|---|---|---|
| 1 | `fix-test-sh-python3.md` | python3 探测 / venv 布局跨平台 | Python 候选探测链、bin+Scripts 双布局、`-m pip`、trap 清理、默认装本地工作树 |
| 2 | `fix-test-sh-python3-patch2.md` | MSYS 路径 cygpath 转换 | `to_native_path()`、`VENV_DIR_NATIVE` / `PACKAGE_SOURCE_NATIVE` |
| 3 | `fix-test-sh-functional.md` | 功能段对齐真实 CLI | 删除不存在的 `read`/`search*` 子命令，重写为 14 项真实 CLI 探测 |

### 2.1 方案一：python3 探测与 venv 布局（fix-test-sh-python3.md）

**修复前的故障面：**

- 硬编码 `python3`：Windows Git Bash 通常只有 `python` 或 Python Launcher `py`，`set -e` 下命令解析失败即静默退出。
- 硬编码 `source venv/bin/activate`：Windows venv 使用 `venv/Scripts/activate`。
- 裸 `pip` 调用：PATH 未正确激活或遇到 PEP 668 限制时指向错误解释器。
- `pip ... | tail -1` 管道：`tail` 的成功状态会掩盖 pip 失败。
- 默认从 GitHub `archive/main.zip` 安装：验证的是远端分支而不是当前工作树。

**修复后的行为：**

- `set -Eeuo pipefail` 严格模式；所有探测命令放在 `if` 条件中，失败不会触发无上下文的提前退出，而是汇总到统一错误分支。
- Python 探测链 `python3` → `python` → `py -3`，每个候选都要实际启动并通过 `sys.version_info >= (3, 10)` 检查；全部失败时输出明确错误。
- venv 激活脚本和 venv 内 Python 均按 `bin/` 与 `Scripts/` 双布局探测。
- 安装一律 `"$VENV_PYTHON" -m pip install`，输出完整捕获，失败时打印并退出。
- 默认安装源为 `SCRIPT_DIR`（当前工作树），`AGENT_REACH_TEST_SOURCE` 可显式覆盖为远端 archive。
- 清理迁移到 `trap cleanup EXIT`（含 `INT`/`TERM`）：先 `deactivate` 再删临时目录；Windows 文件锁导致删除失败时只输出警告，不覆盖原始测试结果。
- `TMPDIR` 若从 Windows 环境继承了 `C:\...` 形式路径，先用 `cygpath -u` 转成 POSIX 路径再交给 `mktemp`。

### 2.2 方案二：MSYS 路径 cygpath 转换（fix-test-sh-python3-patch2.md）

**修复前的故障面：**

方案一落地后，Windows Git Bash 上仍报"未找到 venv 激活脚本"。根因：**MSYS2 只对已存在的路径做自动参数转换**。`mktemp` 返回的 `/tmp/agent-reach-test.XXXXXX/venv` 在创建 venv 前尚不存在，原生 Windows Python 按 CRT 规则把它解析成**当前盘符下**的 `D:\tmp\...\venv`——venv 被建到了一个 Bash 永远找不到的地方。

**修复后的行为：**

- 新增 `to_native_path()` 辅助函数：有 `cygpath` 时对本地路径执行 `cygpath -w` 转成 Windows 反斜杠路径；URL（`*://*`）原样返回；无 `cygpath` 的系统（Linux/macOS）原样返回。
- 只有**传给 Windows 原生 Python 的两个参数**使用转换后的变量：
  - `python -m venv "$VENV_DIR_NATIVE"`
  - `"$VENV_PYTHON" -m pip install "$PACKAGE_SOURCE_NATIVE"`
- Bash 侧的文件检查（`[ -f ]`、`[ -x ]`）、`source` 激活和错误信息继续使用 POSIX 变量（`VENV_DIR`、`PACKAGE_SOURCE`）——POSIX 路径正是 Bash 的正确接口。

### 2.3 方案三：功能段对齐真实 CLI（fix-test-sh-functional.md）

**修复前的故障面：**

- 旧功能段调用 `agent-reach read`、`search`、`search-github`、`search-twitter` 等子命令，但当前 CLI（argparse）根本没有注册这些命令——每项都刷 `invalid choice` 的 usage 错误。Agent Reach 的定位是"安装器 + doctor + 配置工具"，实际读取/搜索由 Agent 直接调用上游工具完成。
- 旧判定规则"输出含 `http` 就 PASS"会掩盖 doctor 的坏状态；doctor 用 Rich markup `[!]`/`[X]` 而不是 ⚠️，旧的 SKIP 关键词也匹配不到中文的"未安装/未配置"。

**修复后的行为：**

- `test_it` 升级为接受 `名称 命令 [期望正则] [SKIP 正则]`：先匹配每项自己的语义关键词，再用统一的环境缺失/网络不可用正则降级为 SKIP。
- 14 项测试全部替换为真实、快速、无凭据的 CLI 冒烟：

| 分段 | 条目 | 判定要点 |
|---|---|---|
| 📖 CLI 诊断与命令测试（7 项） | doctor 渠道状态、doctor/transcribe/format/skill `--help`、`format xhs` handler（`printf '{}'` 管道冒烟）、version | 命中 `Agent Reach 状态`、`usage: agent-reach ...`、`^\{`、`^Agent Reach v...` 等特征 |
| 🔍 CLI 更新与参数测试（7 项） | `timeout 15s agent-reach check-update`、check-update/watch/setup/install/configure/uninstall `--help` | check-update 成功特征 PASS；网络/DNS/超时降级 SKIP；带副作用的命令只测 `--help`，不真实执行 |

- 有副作用或需要凭据的命令（setup、install、configure、uninstall、真实 transcribe、平台搜索）一律不进入功能段；其覆盖由前置的 `install --env=auto` / `doctor` 阶段和 `--help` 探测承担。

---

## 3. 各平台使用方式与预期输出

统一入口：在仓库根目录执行 `bash test.sh`。前置要求：可执行的 Python 3.10+，能访问 PyPI 的网络。

### 3.1 Windows（Git Bash）

```bash
cd /d/code/github/Agent-Reach
bash test.sh
```

- Python 来自 python.org 安装包时，候选探测通常命中 `python` 或 `py -3`（`python3` 多为 Microsoft Store 空壳别名，会被自动跳过）。
- venv 为 `Scripts/` 布局；`/tmp` 由 Git Bash 映射。
- `cygpath` 随 Git for Windows 自带；传给原生 Python 的 venv/安装源路径会被转成 `D:\...` 反斜杠形式（见 §2.2）。
- `TMPDIR` 若被设为 `C:\...` 形式会先转成 POSIX 路径。
- Git for Windows 的 `/usr/bin` 自带 GNU `timeout`；若你的环境没有，check-update 一项会受影响（见 §4）。

### 3.2 macOS

```bash
cd /path/to/Agent-Reach
bash test.sh
```

- 脚本兼容系统自带 bash 3.2。
- 推荐 Homebrew Python（`python3`）；Xcode CLT 的 `python3` 桩首次运行会触发安装提示。
- 无 `cygpath`，`to_native_path()` 原样返回路径，行为与 Linux 一致。
- venv 为 `bin/` 布局。

### 3.3 Linux

```bash
cd /path/to/Agent-Reach
bash test.sh
```

- `python3` 直接命中；Debian/Ubuntu 若缺 venv 支持会报"不支持 venv/ensurepip"，安装 `python3-venv` 即可（见 §4）。
- venv 为 `bin/` 布局。

### 3.4 预期输出骨架

```text
╔════════════════════════════════════════════╗
║    👁️  Agent Reach 完整测试                ║
╚════════════════════════════════════════════╝

📦 创建测试环境...
📥 从 GitHub 安装...          # 文案沿用旧称；默认实际安装的是本地工作树
<pip 输出最后一行>

⚙️  运行 install...
<agent-reach install --env=auto 的渠道安装报告>

🩺 运行 doctor...
<Agent Reach 状态报告，状态：N/M 个渠道可用>

📖 CLI 诊断与命令测试
  doctor 渠道状态 ... ✅
  doctor 帮助 ... ✅
  transcribe 帮助 ... ✅
  format 帮助 ... ✅
  format xhs handler ... ✅
  skill 帮助 ... ✅
  version ... ✅

🔍 CLI 更新与参数测试
  check-update ... ✅        # 网络不通/限流时为 ⏭️  (跳过 — 缺依赖)
  check-update 帮助 ... ✅
  watch 帮助 ... ✅
  setup 帮助 ... ✅
  install 参数帮助 ... ✅
  configure 参数帮助 ... ✅
  uninstall 参数帮助 ... ✅

════════════════════════════════════════════
  ✅ 通过: 14   ❌ 失败: 0   ⏭️  跳过: 0
════════════════════════════════════════════

🎉 全部通过！
```

- 全部顺利时：14 通过、0 失败；离线或 GitHub 限流时 check-update 记 SKIP，仍算通过（`FAIL=0` 即退出码 0）。
- 任何一步失败（Python 缺失、venv 创建失败、pip 安装失败、`agent-reach` 未进 PATH、FAIL > 0）都会以非零退出码结束，并由 trap 清理临时目录。
- 验证远端包而非工作树：`AGENT_REACH_TEST_SOURCE='https://github.com/fcmyoo/Agent-Reach/archive/main.zip' bash test.sh`。

---

## 4. 常见问题排查表

| 症状 | 原因 | 解决方案 |
|---|---|---|
| **Codex CLI 在 Windows git-bash 上报 `CryptUnprotectData failed (2148073483)`**，workspace-write 沙箱无法访问工作区/凭据错误 | Codex 的 `workspace-write` 沙箱在 Windows（MINGW/MSYS/CYGWIN）上存在 DPAPI bug，与 test.sh 本身无关，是 Agent 编排环境的问题 | 改用 `codex exec --sandbox danger-full-access`；`scripts/dual-engine.sh` 已按 `uname -s` 自动降级。范围安全改由路径白名单、任务工作目录、版本控制和审计日志保证 |
| **Git Bash 上报"未找到 venv 激活脚本"**，venv 实际建在 `D:\tmp\...` 等意外位置 | MSYS2 只对**已存在**的路径做自动参数转换；venv 创建前的 `/tmp/.../venv` 不存在，原生 Windows Python 按 CRT 规则解析到当前盘符根目录下 | 现行 test.sh 已修复：`to_native_path()`（`cygpath -w`）生成 `VENV_DIR_NATIVE`/`PACKAGE_SOURCE_NATIVE`，只转换传给原生 Python 的参数，Bash 侧继续用 POSIX 路径。若你维护的是旧版脚本，按 `docs/plans/fix-test-sh-python3-patch2.md` 打补丁 |
| **`claude -p ... --max-turns N` 非零退出，打印 `Error: Reached max turns (N)`**，看起来"什么都没做" | 撞 max-turns 时进程非零退出且收尾总结被丢弃，但**文件改动可能已经落盘**；不能仅凭退出码判定"没有改动" | 先 `git status` / `git diff` 并跑测试核实：改动完整则直接进入验证；不完整则调大轮数重跑。参考值：小任务 4、常规 8、调试 6+重新规划；`dual-engine.sh` 默认 `CLAUDE_TURNS=40`（实测复杂"读方案+多段 diff+验证"需约 16 轮） |
| 报"错误：需要可执行的 Python 3.10+（尝试过 python3、python、py -3）" | `python3` 是 Windows Store 空壳别名，或已装 Python 版本低于 3.10 | 从 python.org 安装 Python 3.10+；脚本会自动沿 `python3` → `python` → `py -3` 回退，无需改脚本 |
| Linux 上报"$PYTHON 不支持 venv/ensurepip" | Debian/Ubuntu 系发行版把 venv 拆成独立包 | `sudo apt install python3-venv` 后重跑 |
| check-update 一项显示 ⏭️ | GitHub 不可达 / DNS 失败 / 速率限制 / 15s 超时；个别 Git Bash 环境无 GNU `timeout` | 这是**设计内的 SKIP**，不阻塞其余测试。网络恢复后重跑即可；无 `timeout` 命令的环境不要裸跑无限重试，可将该条降级为 `agent-reach check-update --help` |
| 收尾时打印"警告：临时目录仍被占用，无法删除：/tmp/agent-reach-test.XXXXXX" | Windows 文件锁：子进程仍占用临时目录内文件 | 不影响测试结论；稍后手动 `rm -rf` 该目录即可 |
| 功能段出现 `invalid choice: 'read'` 之类的 usage 刷屏 | 运行的是旧版 test.sh——`read`/`search*` 子命令在当前 CLI 中不存在 | 更新到现行 test.sh（功能段为 14 项真实 CLI 探测，见 §2.3）；Agent Reach 是安装器/体检/路由层，读取搜索由 Agent 直接调用上游工具 |

---

## 相关文档

- `docs/plans/fix-test-sh-python3.md` — Python 探测与 venv 布局修复方案
- `docs/plans/fix-test-sh-python3-patch2.md` — MSYS 路径 cygpath 转换补丁方案
- `docs/plans/fix-test-sh-functional.md` — 功能测试段对齐真实 CLI 方案
- `docs/troubleshooting.md` — 各平台渠道的运行时问题（Cookie、代理等）
- `scripts/dual-engine.sh` — 双引擎协作模板（Claude Code 实现 + Codex 验证，含 DPAPI 沙箱自动降级与 max-turns 处理）
