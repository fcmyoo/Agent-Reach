#!/usr/bin/env bash
# =============================================================================
# dual-engine.sh — 双引擎协作模板（Claude Code 实现 + Codex 验证）
# =============================================================================
# 用途：Hermes 编排 Claude Code / Codex CLI 在项目里执行任务的完整模板。
# 流程：Phase 1 Claude Code 写代码 → Phase 2 Codex 跑测试 + 审查改动 → 汇报
#
# 用法：
#   ./scripts/dual-engine.sh "给 cli.py 的 --version 加仓库名和提交号"
#   TASK_FILE=task.md ./scripts/dual-engine.sh        # 从文件读任务
#   CLAUDE_TURNS=30 CODEX_SANDBOX=workspace-write ./scripts/dual-engine.sh "..."
#
# 环境变量（均可覆盖）：
#   CLAUDE_TURNS    Claude Code 内部循环轮数上限（默认 40。实测复杂"读方案+多段
#                    diff 应用+验证"任务需 ~16 轮，20 轮会撞上限；40 轮充裕）
#   CODEX_SANDBOX   auto | workspace-write | danger-full-access（默认 auto）
#   CLAUDE_TOOLS    Claude Code 允许的工具（默认 "Read,Edit,Write,Bash"）
# =============================================================================
set -euo pipefail

TASK="${1:-}"
if [[ -z "$TASK" && -f task.md ]]; then
  TASK="$(cat task.md)"
fi
if [[ -z "$TASK" ]]; then
  echo "用法: $0 \"任务描述\"  或先在本目录写好 task.md"
  exit 1
fi

CLAUDE_TURNS="${CLAUDE_TURNS:-40}"
CLAUDE_TOOLS="${CLAUDE_TOOLS:-Read,Edit,Write,Bash}"
CODEX_SANDBOX="${CODEX_SANDBOX:-auto}"

# ── Codex 沙箱自动选择 ──────────────────────────────────────────────────────
# Windows (git-bash) 上 workspace-write 沙箱有 DPAPI bug
# （CryptUnprotectData failed 2148073483），自动降级为 danger-full-access；
# Linux/macOS 保持推荐的安全沙箱。
if [[ "$CODEX_SANDBOX" == "auto" ]]; then
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) CODEX_SANDBOX="danger-full-access" ;;
    *)                    CODEX_SANDBOX="workspace-write" ;;
  esac
fi

log() { printf '\n\033[1;36m[%s]\033[0m %s\n' "$(date +%H:%M:%S)" "$*"; }

log "任务: $TASK"
log "Claude turns=$CLAUDE_TURNS | Codex sandbox=$CODEX_SANDBOX"

# ── Phase 1: Claude Code 实现（print 模式，免交互、无对话框）────────────────
log "Phase 1/2 — Claude Code 实现"
if ! claude -p "$TASK" \
  --allowedTools "$CLAUDE_TOOLS" \
  --max-turns "$CLAUDE_TURNS" \
  --append-system-prompt "高效执行模式：一次改完，不要反复读取/确认同一文件；不要在无关命令上探索；完成全部编辑后立即用中文总结。" \
  --dangerously-skip-permissions; then
  # 已知行为：claude -p 撞 max-turns 会打印 "Error: Reached max turns (N)" 并以
  # 非零退出，但文件改动可能已经落盘（实测如此），且总结输出会被丢弃。警告后
  # 继续 Phase 2 验证；若验证失败再加大 CLAUDE_TURNS 重跑即可。
  log "⚠️ Claude 在 $CLAUDE_TURNS 轮内未正式收尾（改动可能已写入）。继续 Codex 验证…"
fi

# ── Phase 2: Codex 验证（真实执行测试 + 审查改动）──────────────────────────
log "Phase 2/2 — Codex 验证（跑测试 + 审查改动）"
codex exec --sandbox "$CODEX_SANDBOX" \
  "项目任务已完成（任务原文：$TASK）。请执行收尾验证：
   1) 运行项目测试套件（pytest / uv run pytest / test.sh，按项目实际来）
   2) git diff 审查本次改动，找出问题或遗漏
   3) 用中文汇报：测试统计、失败原因、发现的问题"

log "双引擎协作完成 ✅（Claude 实现 → Codex 验证）"
