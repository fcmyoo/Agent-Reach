# test.sh Windows Git Bash 路径转换补丁方案

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 Windows Git Bash 下 MSYS2 不会转换尚不存在路径的问题，确保原生 Windows Python 创建的 venv 与 Bash 检查、激活使用同一目录。

**Architecture:** 保留 Bash 侧的 POSIX 路径变量（TEST_DIR、VENV_DIR、ACTIVATE、VENV_PYTHON），仅在调用 Windows 原生 Python 前通过辅助函数生成 Windows 路径变量。cygpath 不存在时原样返回参数；URL 安装源不作为文件路径转换。

**Tech Stack:** Bash 3.2+、Git Bash/MSYS2、cygpath（可选）、Python 3.10+ venv/pip。

---

## 根因与边界

mktemp 返回的 TEST_DIR/VENV_DIR 是 /tmp/...。Git Bash 仅对已存在路径做 MSYS 参数转换；venv 创建前的 /tmp/.../venv 尚不存在，Windows Python 遂按 CRT 规则解析为当前盘符下的 D:\tmp\...。因此 Bash 在 /tmp/.../venv 查找 Scripts/activate 会失败。

本补丁只转换传给原生 Python 的两个参数：

1. python -m venv 使用 VENV_DIR_NATIVE。
2. VENV_PYTHON -m pip install 的本地源使用 PACKAGE_SOURCE_NATIVE。

激活脚本和 VENV_PYTHON 检测继续使用 Bash POSIX 路径。source、[ -f ]、[ -x ] 都由 Bash 执行，不需要转换。

## 精确 diff 建议

### 1. 加入 to_native_path

插入 test.sh 现有 PACKAGE_SOURCE 定义后（Python 探测循环之前）：

    diff
     SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
     PACKAGE_SOURCE="${AGENT_REACH_TEST_SOURCE:-$SCRIPT_DIR}"
    +
    +# 仅转换传给 Windows 原生程序的本地路径；Linux/macOS 无 cygpath 时原样返回。
    +to_native_path() {
    +    local path="$1"
    +    if command -v cygpath >/dev/null 2>&1; then
    +        case "$path" in
    +            *://*) printf '%s\n' "$path" ;;
    +            *) cygpath -w -- "$path" ;;
    +        esac
    +    else
    +        printf '%s\n' "$path"
    +    fi
    +}

上面 diff 中的花括号变量语法应原样保留在 test.sh。*://* 例外保证显式的 https://... 源仍是 URL；默认 SCRIPT_DIR 和本地源会执行 cygpath -w。

### 2. 生成原生路径变量

插入 VENV_DIR="$TEST_DIR/venv" 之后、cleanup() 之前：

    diff
     VENV_DIR="$TEST_DIR/venv"
    +VENV_DIR_NATIVE="$(to_native_path "$VENV_DIR")"
    +PACKAGE_SOURCE_NATIVE="$(to_native_path "$PACKAGE_SOURCE")"

不要覆盖 VENV_DIR/PACKAGE_SOURCE；Bash 检查、激活和错误信息仍使用 POSIX 变量。

### 3. venv 创建参数

替换准备环境段（当前约第 63 行）的最后一个参数：

    diff
    -if ! "$PYTHON" "${PYTHON_ARGS[@]}" -m venv "$VENV_DIR"; then
    +if ! "$PYTHON" "${PYTHON_ARGS[@]}" -m venv "$VENV_DIR_NATIVE"; then

这样原生 Python 收到类似 D:\\tmp\\agent-reach-test.xxxxxx\\venv 的已转换路径，venv 实际建立在 TEST_DIR 对应目录。

### 4. 激活与 VENV_PYTHON 检测保持不变

不要修改以下现有分支：

    if [ -f "$VENV_DIR/bin/activate" ]; then
        ACTIVATE="$VENV_DIR/bin/activate"
    elif [ -f "$VENV_DIR/Scripts/activate" ]; then
        ACTIVATE="$VENV_DIR/Scripts/activate"
    fi
    source "$ACTIVATE"

    if [ -x "$VENV_DIR/bin/python" ]; then
        VENV_PYTHON="$VENV_DIR/bin/python"
    elif [ -x "$VENV_DIR/Scripts/python.exe" ]; then
        VENV_PYTHON="$VENV_DIR/Scripts/python.exe"
    fi

这些是 Bash 文件操作，POSIX 路径正是正确接口。

### 5. pip 安装源参数

替换安装段（当前约第 96 行）：

    diff
     PIP_OUTPUT=""
    -if ! PIP_OUTPUT="$("$VENV_PYTHON" -m pip install -q "$PACKAGE_SOURCE" 2>&1)"; then
    +if ! PIP_OUTPUT="$("$VENV_PYTHON" -m pip install -q "$PACKAGE_SOURCE_NATIVE" 2>&1)"; then
         echo "$PIP_OUTPUT" >&2
         echo "错误：安装源不可用或依赖安装失败：$PACKAGE_SOURCE" >&2
         exit 1
     fi

错误信息保留原始 PACKAGE_SOURCE；执行参数使用 PACKAGE_SOURCE_NATIVE。URL 因 *://* 分支原样传递，本地 SCRIPT_DIR 在 Windows 下转成 D:\\code\\github\\Agent-Reach。

### 6. Python 探测阶段决策

不跳过 Hermes 自己的 venv Python。实测命中的 hermes-agent\venv\Scripts\python 只要满足 3.10+ 且具备 venv/ensurepip 就是合格引导解释器；本次失败是路径参数格式，不是解释器来源。按路径名排除会在只有该 Python 可用时造成误报。若未来确认该解释器不满足要求，再独立增加规范化路径排除并保留 python3/python/py -3 回退链；这不属于本次功能修复。

## 实施与验收步骤

### Task 1: 加入转换逻辑

Files:
- Modify: test.sh 的 PACKAGE_SOURCE 后和 VENV_DIR 后。

- [ ] 按上述 diff 加入 to_native_path、VENV_DIR_NATIVE、PACKAGE_SOURCE_NATIVE。
- [ ] 确认 cygpath 不存在时原样返回，URL 不被转换。

### Task 2: 替换两个原生 Python 参数

Files:
- Modify: test.sh 的 -m venv 与 -m pip install 两行。

- [ ] 将 venv 参数替换为 VENV_DIR_NATIVE。
- [ ] 将 pip 源参数替换为 PACKAGE_SOURCE_NATIVE；ACTIVATE/VENV_PYTHON 分支不变。

### Task 3: 静态检查与跨平台验收

Files:
- Test: test.sh（不新增测试文件）。

- [ ] 任意 Bash 执行 bash -n test.sh，预期无输出且退出码 0。
- [ ] Windows Git Bash 执行 bash -x test.sh 2>&1 | tee test-sh-patch2.log；trace 应显示 VENV_DIR_NATIVE 为 D:\\...\\agent-reach-test...\\venv，VENV_DIR 仍为 /tmp/.../venv。
- [ ] 同一次运行应依次通过 venv 创建、Scripts/activate 检测、pip 安装，并进入 agent-reach install --env=auto；不得再出现“未找到 venv 激活脚本”。
- [ ] 验证本地源和 URL 源：

    AGENT_REACH_TEST_SOURCE="$PWD" bash test.sh
    AGENT_REACH_TEST_SOURCE='https://github.com/fcmyoo/Agent-Reach/archive/main.zip' bash test.sh

本地源的 PACKAGE_SOURCE_NATIVE 应为 Windows 反斜杠路径；URL 应保持 https://...。
- [ ] Linux/macOS（无 cygpath）以本地源运行，仍发现 venv/bin/activate 并完成安装。

## 验收标准

1. Windows Python 创建的 venv 位于 TEST_DIR 实际位置，而非误解析的 D:\tmp 根目录。
2. Bash 通过 $VENV_DIR/Scripts/activate 激活，并通过 $VENV_DIR/Scripts/python.exe 找到 venv Python。
3. pip 本地安装成功进入 agent-reach install；远程 URL 不被转换。
4. 无 cygpath 的系统原样传递路径；现有 python3/python/py -3 探测逻辑和 Hermes venv 选择行为保持不变。
5. 本轮只新增本方案文档，不修改 test.sh。

## 方案自检

- 已覆盖 venv 参数、pip 源参数、POSIX 激活/检测、cygpath 回退、Hermes venv 决策及 Windows/Linux 验收。
- 每处变更均给出插入位置和替换 diff；无未定义辅助函数或变量。
