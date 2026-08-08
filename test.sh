#!/bin/bash
# Agent Reach 一键完整测试
# 用法: bash test-agent-reach.sh
# 在任何有 Python 3.10+ 的机器上跑就行

set -Eeuo pipefail

echo "╔════════════════════════════════════════════╗"
echo "║    👁️  Agent Reach 完整测试                ║"
echo "╚════════════════════════════════════════════╝"
echo ""

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# 仅转换传给 Windows 原生程序的本地路径；Linux/macOS 无 cygpath 时原样返回。
to_native_path() {
    local path="$1"
    if command -v cygpath >/dev/null 2>&1; then
        case "$path" in
            *://*) printf '%s\n' "$path" ;;
            *) cygpath -w -- "$path" ;;
        esac
    else
        printf '%s\n' "$path"
    fi
}

# 仓库根目录直接使用原生路径：本机 MSYS 不会把 POSIX 路径自动转换给 Windows 程序
# （实测 pip/python 收到字面 /d/... 会解析失败），cygpath -w 显式转换才能被
# Windows python/pip/pytest 正确打开；Linux/macOS 无 cygpath 时原样等于 POSIX 路径。
REPO_ROOT="$(to_native_path "$SCRIPT_DIR")"
PACKAGE_SOURCE="${AGENT_REACH_TEST_SOURCE:-$SCRIPT_DIR}"

# 优先复用项目自带的 .venv（若存在），否则回退到系统 Python 探测。
PYTHON_CMD=()
if [ -x "$REPO_ROOT/.venv/bin/python" ]; then
    PYTHON_CMD=("$REPO_ROOT/.venv/bin/python")
elif [ -x "$REPO_ROOT/.venv/Scripts/python.exe" ]; then
    PYTHON_CMD=("$REPO_ROOT/.venv/Scripts/python.exe")
fi

# 选择能实际启动且版本满足项目要求的解释器；Windows Store 的 python3 别名会被跳过。
PYTHON=""
PYTHON_ARGS=()
if [ "${#PYTHON_CMD[@]}" -gt 0 ] \
    && "${PYTHON_CMD[0]}" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)' >/dev/null 2>&1; then
    PYTHON="${PYTHON_CMD[0]}"
fi
for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1 \
        && "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)' >/dev/null 2>&1; then
        PYTHON="$(command -v "$candidate")"
        break
    fi
done
if [ -z "$PYTHON" ] && command -v py >/dev/null 2>&1 \
    && py -3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)' >/dev/null 2>&1; then
    PYTHON="$(command -v py)"
    PYTHON_ARGS=(-3)
fi
if [ -z "$PYTHON" ]; then
    echo "错误：需要可执行的 Python 3.10+（尝试过 python3、python、py -3）。" >&2
    exit 1
fi

TEST_DIR=""
TMP_ROOT="${TMPDIR:-/tmp}"
# Git Bash 可能从 Windows 环境继承 C:\...；mktemp 需要 POSIX 路径。
if command -v cygpath >/dev/null 2>&1 && [[ "$TMP_ROOT" == [A-Za-z]:* ]]; then
    TMP_ROOT="$(cygpath -u "$TMP_ROOT")"
fi
if ! TEST_DIR="$(mktemp -d "$TMP_ROOT/agent-reach-test.XXXXXX" 2>/dev/null)"; then
    echo "错误：无法在 $TMP_ROOT 创建临时测试目录。请检查 TMPDIR 和目录权限。" >&2
    exit 1
fi
# 规范化物理路径（Windows/MSYS 下也拿到真实位置），并隔离 HOME 防止真实用户配置干扰测试。
TEST_DIR=$(cd "$TEST_DIR" && pwd -P)
export HOME="$TEST_DIR/home"
export XDG_CONFIG_HOME="$TEST_DIR/config"
mkdir -p "$HOME" "$XDG_CONFIG_HOME"
VENV_DIR="$TEST_DIR/venv"
VENV_DIR_NATIVE="$(to_native_path "$VENV_DIR")"
PACKAGE_SOURCE_NATIVE="$(to_native_path "$PACKAGE_SOURCE")"

cleanup() {
    if declare -F deactivate >/dev/null 2>&1; then
        deactivate >/dev/null 2>&1 || true
    fi
    if [ -n "${TEST_DIR:-}" ] && [ -d "$TEST_DIR" ]; then
        rm -rf -- "$TEST_DIR" 2>/dev/null || \
            echo "警告：临时目录仍被占用，无法删除：$TEST_DIR" >&2
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# ── 1. 准备干净环境 ──
echo "📦 创建测试环境..."
if ! "$PYTHON" "${PYTHON_ARGS[@]}" -m venv "$VENV_DIR_NATIVE"; then
    echo "错误：$PYTHON 不支持 venv/ensurepip，无法创建隔离环境。" >&2
    echo "请安装带 venv 支持的 Python 3.10+（Linux 可能需要 python3-venv）。" >&2
    exit 1
fi

ACTIVATE=""
if [ -f "$TEST_DIR/venv/bin/activate" ]; then
    ACTIVATE="$TEST_DIR/venv/bin/activate"
elif [ -f "$TEST_DIR/venv/Scripts/activate" ]; then
    ACTIVATE="$TEST_DIR/venv/Scripts/activate"
fi
if [ -z "$ACTIVATE" ]; then
    echo "错误：未找到 venv 激活脚本（bin/activate 或 Scripts/activate）。" >&2
    exit 1
fi
if ! source "$ACTIVATE"; then
    echo "错误：无法激活 venv：$ACTIVATE" >&2
    exit 1
fi

if [ -x "$VENV_DIR/bin/python" ]; then
    VENV_PYTHON="$VENV_DIR/bin/python"
elif [ -x "$VENV_DIR/Scripts/python.exe" ]; then
    VENV_PYTHON="$VENV_DIR/Scripts/python.exe"
else
    echo "错误：未找到 venv 内的 Python 可执行文件。" >&2
    exit 1
fi

# ── 2. 安装 ──
echo "📥 安装本地工作树（含 dev 依赖）..."
PIP_OUTPUT=""
if ! PIP_OUTPUT="$("$VENV_PYTHON" -m pip install --quiet -c "$REPO_ROOT/constraints.txt" -e "$REPO_ROOT[dev]" 2>&1)"; then
    echo "$PIP_OUTPUT" >&2
    echo "错误：安装源不可用或依赖安装失败：$PACKAGE_SOURCE" >&2
    exit 1
fi
printf '%s\n' "$PIP_OUTPUT" | tail -1
echo ""

# ── 3. 自动配置 ──
echo "⚙️  运行 install（安全模式）..."
if ! command -v agent-reach >/dev/null 2>&1; then
    echo "错误：安装完成但 PATH 中没有 agent-reach；请检查 venv 激活脚本。" >&2
    exit 1
fi
agent-reach install --env=auto --safe 2>&1
echo "  dry-run 预览（--system --dry-run，不落盘）："
agent-reach install --env=auto --system --dry-run 2>&1 | tail -5
echo ""

# ── 4. 诊断 ──
echo "🩺 运行 doctor（JSON）..."
agent-reach doctor --json 2>&1 | head -30
echo ""

# ── 5. 逐个测试 ──
PASS=0
FAIL=0
SKIP=0

test_it() {
    local name="$1"
    local command="$2"
    local expected="${3:-📖|🔗|http}"
    local skip_pattern="${4:-⚠️|not installed|not configured|\\[!\\]|\\[X\\]|未安装|未配置|未认证|未登录|需要配置|需要登录|无法检查更新|超时|timeout|DNS|连接失败|速率限制|__CHECK_UPDATE_TIMEOUT__}"
    echo -n "  $name ... "
    output=$(eval "$command" 2>&1) || true
    if printf '%s\n' "$output" | grep -Eq "$expected"; then
        echo "✅"
        PASS=$((PASS+1))
    elif printf '%s\n' "$output" | grep -Eq "$skip_pattern"; then
        echo "⏭️  (跳过 — 缺依赖)"
        SKIP=$((SKIP+1))
    else
        echo "❌"
        echo "    $(printf '%s\n' "$output" | head -2)"
        FAIL=$((FAIL+1))
    fi
}

echo "📖 CLI 诊断与命令测试"
test_it "doctor 渠道状态" "agent-reach doctor" "Agent Reach 状态|状态：.*[0-9]+/[0-9]+"
test_it "doctor 帮助" "agent-reach doctor --help" "usage: agent-reach doctor|--json"
test_it "transcribe 帮助" "agent-reach transcribe --help" "usage: agent-reach transcribe|source|--provider"
test_it "format 帮助" "agent-reach format --help" "usage: agent-reach format|\\{xhs\\}"
test_it "format xhs handler" "printf '%s\n' '{}' | agent-reach format xhs" "^\\{" "Error: no input|invalid JSON"
test_it "skill 帮助" "agent-reach skill --help" "usage: agent-reach skill|--install|--uninstall"
test_it "version" "agent-reach version" "^Agent Reach v[0-9]+\\.[0-9]+\\.[0-9]+"

echo ""
echo "🔍 CLI 更新与参数测试"
test_it "check-update" "timeout 15s agent-reach check-update || printf '%s\n' '__CHECK_UPDATE_TIMEOUT__'" "已是最新版本|最新版本:|最新提交:"
test_it "check-update 帮助" "agent-reach check-update --help" "usage: agent-reach check-update"
test_it "watch 帮助" "agent-reach watch --help" "usage: agent-reach watch|scheduled tasks"
test_it "setup 帮助" "agent-reach setup --help" "usage: agent-reach setup|Interactive configuration wizard"
test_it "install 参数帮助" "agent-reach install --help" "usage: agent-reach install|--dry-run|--safe"
test_it "configure 参数帮助" "agent-reach configure --help" "usage: agent-reach configure|--from-browser"
test_it "uninstall 参数帮助" "agent-reach uninstall --help" "usage: agent-reach uninstall|--dry-run"

echo ""
echo "════════════════════════════════════════════"
echo "  ✅ 通过: $PASS   ❌ 失败: $FAIL   ⏭️  跳过: $SKIP"
echo "════════════════════════════════════════════"

# ── 6. pytest 全量回归 ──
echo ""
echo "🧪 运行 pytest 全量测试..."
if "$VENV_PYTHON" -m pytest "$REPO_ROOT/tests" -q 2>&1 | tail -5; then
    echo "✅ pytest 全量通过"
else
    echo "❌ pytest 存在失败（见上方输出）"
fi

if [ $FAIL -eq 0 ]; then
    echo ""
    echo "🎉 全部通过！"
else
    echo ""
    echo "⚠️  有 $FAIL 个测试失败，请检查上面的输出"
    exit 1
fi
