# test.sh Python/venv 跨平台兼容修复 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让项目根目录的 `test.sh` 在 Windows Git Bash、macOS 和 Linux 上都能可靠选择可用的 Python、创建并激活 venv、通过 venv 内的 Python 安装和执行 Agent Reach，同时保证失败时有清晰错误并完成清理。

**Architecture:** 只修改 `test.sh` 的启动、环境创建、安装和清理部分。启动阶段用 `PYTHON` 路径加参数数组探测真实可执行的 Python 3.10+（依次尝试 `python3`、`python`、`py -3`），创建 venv 后同时识别 POSIX 的 `bin` 布局和 Windows 的 `Scripts` 布局。安装始终调用 venv Python 的 `-m pip`；测试命令继续使用激活后的 `agent-reach`，并通过 `EXIT` trap 统一清理。

**Tech Stack:** Bash 3.2+（Git Bash、macOS、Linux）、Python 3.10+、标准库 `venv`/`ensurepip`、`pip`、GitHub archive（仅作为可选外部安装源）。

---

## 根因与目标行为

- 第 16 行固定调用 `python3`；Windows Git Bash 通常只有 `python`，也可能只有 Python Launcher `py`。`set -e` 会在命令解析失败时立即退出。
- 第 17 行固定 source `venv/bin/activate`；Windows venv 使用 `venv/Scripts/activate`。
- 第 21 行调用裸 `pip`，PATH 未正确激活或系统存在 PEP 668 限制时可能指向错误解释器或失败；应改为 venv Python 的 `-m pip`。
- 仅有 `set -e` 时，`pip ... | tail -1` 的管道可能以 `tail` 的成功状态掩盖 pip 失败；应启用 `pipefail` 或移除该管道并显式检查返回值。
- 当前默认从 GitHub `archive/main.zip` 安装，验证的是远端分支而非工作树；默认应安装脚本所在仓库目录，远端 archive 作为显式覆盖项。

## 文件边界

- **Modify:** `test.sh:6-21`，加入严格模式、Python/临时目录探测、venv 创建/激活和 venv Python 选择。
- **Modify:** `test.sh:24-31`，使用 venv Python 安装包并验证 `agent-reach` 入口。
- **Modify:** `test.sh:81-92`，把清理迁移到 trap，处理退出、信号和 Windows 文件锁。
- **Create:** `docs/plans/fix-test-sh-python3.md`（本方案文件）。
- 现有工作树中 `test.sh` 已有用户修改，实施时只合并下列兼容性 hunk，不回退其余变更。

## 具体修改建议

### Task 1: 启动阶段选择 Python 并创建 venv

**Files:**
- Modify: `test.sh:6-17`

- [ ] **Step 1: 替换严格模式和硬编码 Python/临时目录代码。** 将现有 `set -e` 到 `source` 代码替换为以下 hunk（保留前后的输出文案）：

```diff
-set -e
+set -Eeuo pipefail
+
+SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
+PACKAGE_SOURCE="${AGENT_REACH_TEST_SOURCE:-$SCRIPT_DIR}"
+
+# 选择能实际启动且版本满足项目要求的解释器；Windows Store 的 python3 别名会被跳过。
+PYTHON=""
+PYTHON_ARGS=()
+for candidate in python3 python; do
+    if command -v "$candidate" >/dev/null 2>&1 \
+        && "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)' >/dev/null 2>&1; then
+        PYTHON="$(command -v "$candidate")"
+        break
+    fi
+done
+if [ -z "$PYTHON" ] && command -v py >/dev/null 2>&1 \
+    && py -3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)' >/dev/null 2>&1; then
+    PYTHON="$(command -v py)"
+    PYTHON_ARGS=(-3)
+fi
+if [ -z "$PYTHON" ]; then
+    echo "错误：需要可执行的 Python 3.10+（尝试过 python3、python、py -3）。" >&2
+    exit 1
+fi
+
+TEST_DIR=""
+TMP_ROOT="${TMPDIR:-/tmp}"
+# Git Bash 可能从 Windows 环境继承 C:\\...；mktemp 需要 POSIX 路径。
+if command -v cygpath >/dev/null 2>&1 && [[ "$TMP_ROOT" == [A-Za-z]:* ]]; then
+    TMP_ROOT="$(cygpath -u "$TMP_ROOT")"
+fi
+if ! TEST_DIR="$(mktemp -d "$TMP_ROOT/agent-reach-test.XXXXXX" 2>/dev/null)"; then
+    echo "错误：无法在 $TMP_ROOT 创建临时测试目录。请检查 TMPDIR 和目录权限。" >&2
+    exit 1
+fi
+VENV_DIR="$TEST_DIR/venv"
+
+cleanup() {
+    if declare -F deactivate >/dev/null 2>&1; then
+        deactivate >/dev/null 2>&1 || true
+    fi
+    if [ -n "${TEST_DIR:-}" ] && [ -d "$TEST_DIR" ]; then
+        rm -rf -- "$TEST_DIR" 2>/dev/null || \
+            echo "警告：临时目录仍被占用，无法删除：$TEST_DIR" >&2
+    fi
+}
+trap cleanup EXIT
+trap 'exit 130' INT
+trap 'exit 143' TERM
+
+echo "创建测试环境..."
+if ! "$PYTHON" "${PYTHON_ARGS[@]}" -m venv "$VENV_DIR"; then
+    echo "错误：$PYTHON 不支持 venv/ensurepip，无法创建隔离环境。" >&2
+    echo "请安装带 venv 支持的 Python 3.10+（Linux 可能需要 python3-venv）。" >&2
+    exit 1
+fi
+
+ACTIVATE=""
+if [ -f "$VENV_DIR/bin/activate" ]; then
+    ACTIVATE="$VENV_DIR/bin/activate"
+elif [ -f "$VENV_DIR/Scripts/activate" ]; then
+    ACTIVATE="$VENV_DIR/Scripts/activate"
+fi
+if [ -z "$ACTIVATE" ]; then
+    echo "错误：未找到 venv 激活脚本（bin/activate 或 Scripts/activate）。" >&2
+    exit 1
+fi
+if ! source "$ACTIVATE"; then
+    echo "错误：无法激活 venv：$ACTIVATE" >&2
+    exit 1
+fi
+
+if [ -x "$VENV_DIR/bin/python" ]; then
+    VENV_PYTHON="$VENV_DIR/bin/python"
+elif [ -x "$VENV_DIR/Scripts/python.exe" ]; then
+    VENV_PYTHON="$VENV_DIR/Scripts/python.exe"
+else
+    echo "错误：未找到 venv 内的 Python 可执行文件。" >&2
+    exit 1
+fi
```

- [ ] **Step 2: 保留 `set -e` 的可预期语义。** 所有探测命令必须位于 `if` 条件中；这样“命令不存在/版本不满足”的非零状态不会提前触发 `set -e`，而是汇总到统一错误分支。`set -u` 要求先初始化 `PYTHON`、`PYTHON_ARGS`、`TEST_DIR`、`ACTIVATE`。

### Task 2: 通过 venv Python 安装并进入后续流程

**Files:**
- Modify: `test.sh:20-31`（应用 Task 1 后按新行号定位安装段）

- [ ] **Step 1: 用 `python -m pip` 替换裸 pip 和会吞错的管道。** 将安装段改为：

```diff
 echo "从 GitHub 安装..."
-pip install -q https://github.com/fcmyoo/Agent-Reach/archive/main.zip 2>&1 | tail -1
+PIP_OUTPUT=""
+if ! PIP_OUTPUT="$("$VENV_PYTHON" -m pip install -q "$PACKAGE_SOURCE" 2>&1)"; then
+    echo "$PIP_OUTPUT" >&2
+    echo "错误：安装源不可用或依赖安装失败：$PACKAGE_SOURCE" >&2
+    exit 1
+fi
+printf '%s\n' "$PIP_OUTPUT" | tail -1
 echo ""
```

`PACKAGE_SOURCE` 默认是 `SCRIPT_DIR`，因此测试当前工作树；需要验证远端包时显式执行 `AGENT_REACH_TEST_SOURCE='https://github.com/fcmyoo/Agent-Reach/archive/main.zip' bash test.sh`。在 venv 中不添加 `--break-system-packages`；该参数只适用于绕过系统 Python 的 PEP 668，当前路径已经隔离。

- [ ] **Step 2: 安装后确认 CLI 来自当前 venv。** 在 `agent-reach install` 前加入：

```bash
if ! command -v agent-reach >/dev/null 2>&1; then
    echo "错误：安装完成但 PATH 中没有 agent-reach；请检查 venv 激活脚本。" >&2
    exit 1
fi
```

保留后续 `agent-reach install --env=auto` 和 `agent-reach doctor`；它们仍受 `set -e` 保护，失败即停止并由 trap 清理。

### Task 3: 清理、错误处理和兼容性验证

**Files:**
- Modify: `test.sh:81-92`（应用前述增量后按清理段定位）

- [ ] **Step 1: 删除末尾的手工清理。** 移除：

```diff
-deactivate 2>/dev/null || true
-rm -rf "$TEST_DIR"
```

Task 1 的 `EXIT` trap 会覆盖成功和 `set -e` 失败；`INT`/`TERM` handler 先以非零状态退出，再由 `EXIT` 统一清理。`cleanup` 中的 `deactivate` 已容错，`rm -rf --` 失败只输出警告，不得让清理错误覆盖原始测试结果。

- [ ] **Step 2: 处理 Git Bash 的临时目录和文件锁。** `mktemp -d` 返回的 `/tmp/...` 是 Git Bash 的 POSIX 路径，传给 Windows `python.exe` 时由 MSYS 转换；所有路径必须双引号包裹。若 `rm -rf` 因 Python/Node 子进程仍占用文件失败，保留警告并记录目录，不能在 trap 中再次 `exit`。必要时在 `agent-reach doctor` 前确认不会启动长期驻留进程。

- [ ] **Step 3: 验证 GitHub archive URL。** 不把 archive URL 当作默认本地测试输入。若需要保留远端回归，先确认仓库大小写、`main` 分支和 `pyproject.toml` 在 archive 中存在，并在网络可用环境执行：

```bash
python -m pip download --no-deps --dest /tmp/agent-reach-url-check \
  https://github.com/fcmyoo/Agent-Reach/archive/main.zip
```

下载失败时应使用本地 `SCRIPT_DIR` 测试；URL 验证属于外部依赖，不应被解释成 Windows Python 修复已经完成。

- [ ] **Step 4: 做静态与运行验收。** 在 Linux/macOS 执行 `bash -n test.sh`；在 Windows Git Bash 执行：

```bash
python --version
bash -n test.sh
bash test.sh
```

日志必须显示选择了可用 Python、成功创建 `venv/Scripts`、安装步骤进入 `agent-reach install`，而不是在 `python3` 或 `bin/activate` 处退出。若本机仅有 `py -3`，应覆盖该分支；若 `python3` 是 Microsoft Store alias，则应回退到 `python`/`py -3` 或给出明确错误。

## 验收标准

1. Windows Git Bash（本机 `python=3.11.15`）运行 `bash test.sh` 至少完成 Python 探测、临时目录创建、`python -m venv`、`Scripts/activate` 激活、`venv\Scripts\python.exe -m pip install`，并进入 `agent-reach install`/`doctor`。
2. macOS/Linux 继续识别 `python3` 和 `venv/bin/activate`，所有安装均由 venv Python 执行。
3. Python 不存在、版本低于 3.10、缺少 `venv/ensurepip`、激活脚本缺失、pip 安装失败时均输出明确错误并退出非零；`set -e` 不会在探测阶段产生无上下文的提前退出。
4. 任意退出路径都会尝试 `deactivate` 和删除临时目录；Windows 文件锁导致删除失败时只留下可定位警告。
5. 默认测试安装当前工作树；远端 archive 仅通过 `AGENT_REACH_TEST_SOURCE` 显式启用，并在启用前完成 URL 可用性验证。

## 实施后自检清单

- [ ] `rg -n 'python3 -m venv|venv/bin/activate|^pip install|pip install .*\\| tail' test.sh` 不再命中旧的硬编码调用。
- [ ] `rg -n 'PYTHON=|PYTHON_ARGS|Scripts/activate|bin/activate|VENV_PYTHON|trap cleanup' test.sh` 能看到全部兼容分支。
- [ ] `git diff -- test.sh` 仅包含本方案列出的兼容性改动，保留用户已将仓库 URL 从旧 owner 改为 `fcmyoo/Agent-Reach` 的修改。
