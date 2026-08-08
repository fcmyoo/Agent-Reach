# 三引擎编排协议 v2

> 版本：v2.0
>
> 依据：`docs/plans/ORCHESTRATION-BOUNDARIES.md`（唯一事实来源）
>
> 适用范围：Hermes 调度、Codex CLI（`gpt-5.6-sol`）规划、Claude Code 编码执行。

## 0. 协议目标与边界

Hermes 是唯一入口和编排者，负责任务定义、路由、上下文封装、状态记录、验证和交付。Codex 负责 L3 深度规划，也可以承担需要思考的非编码规划；Claude Code 只承担编码执行，不重做架构设计；Hermes 直接处理 L1 简单任务。

协议边界：

- 用户显式指定引擎时，无条件按指定引擎路由，不以自动复杂度判断覆盖指定。
- 未指定引擎时，严格按 `L3 → L2 → L1` 判定；自动判断拿不准时默认不升级。
- `gpt-5.6-sol` 只用于 L3，不得用于简单任务。
- 非编码任务的深度方案、调研分析或流程设计可交给 Codex；简单非编码任务由 Hermes 直办；非编码执行不派 Claude。
- 编码任务优先自动验证；非编码任务以人工检查和用户反馈为准。
- 产出不满意时同一引擎重做一次并附原因；仍不满意即人工介入，不无限重试。

## 1. 路由决策表

### 1.1 完整判定顺序

Hermes 收到任务后严格按下列顺序执行。前一条件为“否”时才进入下一步。

| 顺序 | 判定问题 | 是：路由与动作 | 否：继续判断 | 判定记录 |
|---:|---|---|---|---|
| 0 | 是否已建立任务定义？ | 生成 `TASK_DEFINED`（任务 ID、原始请求、范围、约束、交付目标） | 补齐定义后再路由 | `task.md` |
| 1 | 用户是否显式指定 `codex`、`claude` 或 `hermes`？ | 直接指派指定引擎，跳过自动复杂度判断 | 进入第 2 步 | `explicit_engine`、原文证据 |
| 2 | 是否为 L3 高思考？需要多步规划、架构设计、方案文档，或需权衡架构/性能/安全等疑难问题 | Codex CLI，固定模型 `gpt-5.6-sol` | 进入第 3 步 | L3 触发项 |
| 3 | 是否为 L2 编码执行？已有冻结方案或明确编码指令，主要工作是写/改/测代码 | Claude Code | 进入第 4 步 | 方案引用、编码范围 |
| 4 | 是否为 L1 直办？读代码、搜资料、简单问答、简单修改、跑测试或小修 | Hermes 直接处理，不派引擎 | 补充事实或请求用户澄清 | L1 依据 |

“用户指定”是第一优先级，适用于编码和非编码任务；它决定指派，不会被后续 L1/L2/L3 自动判断改写。指定场景下 Hermes 仍负责包装上下文、记录命令和执行结果。

### 1.2 非编码任务分支

| 非编码任务 | 复杂度/特征 | 自动归属 | 交付方式 |
|---|---|---|---|
| 写方案、调研分析、流程设计 | 需要多步思考、权衡或形成方案文档 | Codex `gpt-5.6-sol`（L3） | Codex 输出方案，人工检查 |
| 简单问答、搜资料、读代码、简单整理 | 无需设计决策，结果可直接判断 | Hermes 直办（L1） | Hermes 输出，人工检查 |
| 写文档、整理数据、改配置等非编码执行 | 执行性工作，不是写代码 | Hermes 直办；若先需要深度规划则 Codex 规划后仍由 Hermes 执行 | 人工检查，等待用户反馈 |

Claude 的自动路由范围仅为编码执行；它不接收非编码执行任务。混合请求拆成独立子任务，分别路由后合并交付。

### 1.3 典型示例

| 输入 | 结果 |
|---|---|
| “让 codex 设计缓存架构” | 直接指派 Codex，保留用户指定 |
| “让 claude 修复 `foo.py` 的测试失败” | 直接指派 Claude，按编码执行包装 |
| “让 hermes 查一下这个 API 的用法” | Hermes 直办 |
| “设计一套跨模块权限方案” | 未指定且满足 L3，Codex `gpt-5.6-sol` |
| “按现有方案修改两个函数并跑测试” | 未指定且满足 L2，Claude Code |
| “读取这个文件并总结” | 未指定且满足 L1，Hermes 直办 |

## 2. Hermes 侧执行状态机

### 2.1 状态定义

每个任务使用稳定的 `task_id`，所有状态变化追加到 `events.jsonl`。事件至少含 `timestamp`、`task_id`、`from`、`to`、`actor`、`command`、`exit_code`、`artifact_paths`、`reason`。

| 状态 | 含义 | 进入标准 | 离开标准 |
|---|---|---|---|
| `TASK_DEFINED` | 第 0 阶段，任务定义完成 | 已记录原始请求、目标、编码/非编码属性、范围、约束和验收方式 | 路由顺序已执行并产生明确引擎 |
| `DECOMPOSED` | 任务已拆解为可执行子任务 | 每个子任务有目标、依赖、输入、输出和边界 | 子任务均获得路由判定 |
| `ASSIGNED` | 已向目标执行者发出请求 | 请求包含任务 ID、最小上下文、允许范围和预算 | 引擎进程启动并记录命令 |
| `EXECUTING` | 引擎或 Hermes 正在处理 | 请求已启动且 stdout/stderr 正在记录 | 产出返回、超时或进程失败 |
| `VERIFYING` | Hermes 正在验证产出 | 产出已落盘或已准备人工检查 | 自动验证通过/失败，或人工检查完成 |
| `REDO_PENDING` | 等待同引擎一次重做 | 产出不满意且已形成具体原因 | 重做请求发出，回到 `ASSIGNED` |
| `HUMAN_INTERVENTION` | 人工接管 | 同引擎重做一次仍不满意 | 用户指导/接手并建立后续任务 |
| `DELIVERED` | 交付完成 | 验证通过（编码自动；非编码人工）并有交付摘要 | 终态 |

### 2.2 流转图

```text
TASK_DEFINED（第0阶段）
      │
      ▼
DECOMPOSED ──需补资料──> Hermes 采集资料 ──> DECOMPOSED
      │
      ▼
ASSIGNED ──> EXECUTING
      │             │
      │             ├─产出完成──────────────> VERIFYING
      │             ├─进程失败/超时─────────> VERIFYING（先检查已落盘产物）
      │             └─无可验证产出─────────> REDO_PENDING
      ▼
VERIFYING
   ├─编码自动检查通过 ──────────────────────────> DELIVERED
   ├─编码验证失败/方案不一致 ───────────────────> REDO_PENDING
   ├─非编码人工检查通过 ────────────────────────> DELIVERED
   └─非编码人工检查不通过 ──────────────────────> REDO_PENDING

REDO_PENDING ──同一引擎、附原因、仅一次──> ASSIGNED
      └─重做仍不满意────────────────────> HUMAN_INTERVENTION
```

### 2.3 各阶段判定标准

**第 0 阶段：任务定义（`TASK_DEFINED`）**

Hermes 只确认事实，不做深度方案推理。至少记录：

```yaml
task_id: 20260808-0000-example-01
request: "用户原始请求"
work_type: coding | non_coding | mixed
explicit_engine: codex | claude | hermes | null
scope:
  repo: "D:\\code\\github\\Agent-Reach"
  allowed_paths: []
  forbidden_paths: []
acceptance:
  mode: automatic | human
  criteria: []
```

缺少目标、范围或验收标准时，不进入 `ASSIGNED`，先补齐或向用户提问。

**拆解（`DECOMPOSED`）**：识别编码/非编码边界、依赖和共享文件，将混合请求分成可独立路由的子任务。拆解不得改变用户目标。

**指派（`ASSIGNED`）**：冻结目标引擎、工作目录、上下文摘要、允许/禁止范围、超时和命令模板。显式指定时记录原始指派文本；自动路由时记录 L3/L2/L1 证据。

**执行（`EXECUTING`）**：记录完整命令、时间、stdout/stderr、退出码和产物路径。非零退出码不等于无产出，先检查工作区、差异和已生成文件。

**验证（`VERIFYING`）**：编码优先运行测试、`bash -n`、`git diff --check`、`test.sh` 等已有自动检查；关键检查失败不得交付。非编码由 Hermes 做人工可读性、事实一致性和格式检查，交给用户确认。

**兜底（`REDO_PENDING` → `HUMAN_INTERVENTION`）**：重做请求必须引用失败证据和不满意原因，只允许同一引擎再做一次；第二次仍不满意即停止自动循环并人工接管。

## 3. 命令模板（Windows Git Bash）

以下模板在仓库根目录执行。Hermes 应为每次调用建立 `artifacts/<task-id>/`，并将输出重定向到对应日志。

### 3.1 Codex L3 规划

```bash
CODEX_PROMPT=$(cat <<'EOF'
你是 Codex 规划引擎，只输出方案，不执行代码修改。
任务 ID：<task-id>
用户原始请求：<request>
路由依据：<用户指定或 L3 触发项>
仓库：D:/code/github/Agent-Reach
上下文摘要：<context.md 摘要>
请输出：目标、非目标、假设、文件级步骤、接口/数据约束、测试与验收命令、风险、回退和未决问题。
EOF
)
codex --sandbox danger-full-access --model gpt-5.6-sol "$CODEX_PROMPT" 2>&1 \
  | tee "artifacts/$TASK_ID/codex.log"
CODEX_EXIT=${PIPESTATUS[0]}
```

### 3.2 Claude L2 编码执行

```bash
CLAUDE_PROMPT=$(cat <<'EOF'
你是 Claude Code 执行引擎，只执行编码变更，不重设计方案。
任务 ID：<task-id>
严格依据：artifacts/<task-id>/plan.md（版本哈希：<plan-sha256>）
允许修改文件：<allowlist>
禁止修改文件：<denylist>
验收命令：<commands>
完成后输出：修改文件、测试结果、退出码、未完成项和风险。
EOF
)
claude -p "$CLAUDE_PROMPT" --max-turns 40 --allowedTools 'Read,Edit,Write,Bash' 2>&1 \
  | tee "artifacts/$TASK_ID/claude.log"
CLAUDE_EXIT=${PIPESTATUS[0]}
```

### 3.3 Hermes L1 直办与验证

Hermes 直办不启动 Codex 或 Claude，直接使用已有仓库工具和低风险操作：

```bash
rg '<pattern>' .
bash test.sh
```

编码验证由 Hermes 自动运行并记录：

```bash
<plan-defined-test-command> 2>&1 | tee "artifacts/$TASK_ID/verify.log"
VERIFY_EXIT=${PIPESTATUS[0]}
git diff --check
git diff --stat
```

非编码验证不以命令退出码替代人工判断。Hermes 生成 `verify.md`，列出检查项、证据、待用户确认项和反馈入口。

### 3.4 用户显式指定时的 Hermes 包装

显式指定只改变目标引擎，Hermes 仍统一附加任务 ID、原始请求、范围、上下文和验收要求，并记录 `explicit_engine=true`。不得将指定改判为另一引擎。

用户说“让 codex 做 X”时：

```bash
CODEX_PROMPT=$(cat <<'EOF'
用户已显式指定：Codex。
请直接处理以下原始请求，不要改派其他引擎：X
任务 ID：<task-id>
仅在仓库上下文和用户约束内工作；输出可审阅结果并列出未决项。
EOF
)
codex --sandbox danger-full-access --model gpt-5.6-sol "$CODEX_PROMPT"
```

用户说“让 claude 做 X”时：

```bash
CLAUDE_PROMPT=$(cat <<'EOF'
用户已显式指定：Claude Code。
请直接处理以下原始请求，不要改派其他引擎：X
任务 ID：<task-id>
若为编码任务，严格限制在允许文件并运行验收命令；输出修改和测试结果。
EOF
)
claude -p "$CLAUDE_PROMPT" --max-turns 40 --allowedTools 'Read,Edit,Write,Bash'
```

用户说“让 hermes 做 X”时，Hermes 在本地直接执行 X，记录 `explicit_engine=hermes`，不再调用 Codex 或 Claude。

## 4. v1 → v2 差异清单

相对 `docs/multi-engine-orchestration-plan.md`，变更如下：

1. **路由优先级重排**：v1 以规划型/执行型/验证型分类为主；v2 固化为“用户指定 → L3 → L2 → L1”，用户指定不可被覆盖。
2. **复杂度边界收紧**：v1 对高风险、跨模块任务泛化使用 Codex；v2 明确仅满足 L3 才使用 `gpt-5.6-sol`，简单任务禁止升级，拿不准默认不升级。
3. **新增 L1 直办**：读代码、搜资料、简单问答、小修、跑测试等由 Hermes 完成，不派任何引擎。
4. **非编码映射修订**：v1 的 Claude 适用表可含“文档实现”；v2 明确 Claude 只写代码，非编码执行由 Hermes 直办，只有需要深度思考的非编码规划交 Codex。
5. **状态机起点调整**：v2 增加第 0 阶段 `TASK_DEFINED` 和显式 `DECOMPOSED`、`ASSIGNED` 判定，要求先定义任务再拆解和指派。
6. **验证规则分流**：v1 混合自动检查与人工确认；v2 明确编码自动验证为主，非编码以人工检查和用户反馈为准。
7. **兜底规则统一**：v1 可回到 `REPLAN` 或多轮恢复；v2 固定为同一引擎重做一次（附原因），再次不满意即人工介入，不无限循环。
8. **命令参数统一**：Codex 固定 `--sandbox danger-full-access --model gpt-5.6-sol`；Claude 固定 `-p --max-turns 40 --allowedTools 'Read,Edit,Write,Bash'`，并增加显式指派包装模板。
9. **验收口径简化**：v2 按路由无歧义、sol 不被 L1 触发、用户指定不被覆盖、编码/非编码验证方式正确和兜底次数可审计进行验收。

## 5. 验收标准

协议实现满足以下条件，方可判定“可操作”：

1. **路由无歧义**：给定任意任务描述，能先判断是否用户指定，再依次判定 L3、L2、L1，并输出唯一目标引擎及证据；混合任务可拆成可独立路由的子任务。
2. **用户指派不被覆盖**：输入“让 codex/claude/hermes 做 X”时，事件日志保留原文和 `explicit_engine`，实际命令目标与指定一致。
3. **复杂度边界正确**：L3 才调用 `gpt-5.6-sol`；L1 简单任务的执行记录中不存在 Codex 调用；L2 编码任务调用 Claude，且请求明确“只写代码、不重设计”。
4. **非编码边界正确**：非编码规划可调用 Codex；简单非编码和非编码执行由 Hermes 处理；自动路由不会把非编码执行派给 Claude。
5. **状态可追踪**：每个任务均能从 `TASK_DEFINED` 经 `DECOMPOSED`、`ASSIGNED`、`EXECUTING`、`VERIFYING` 到 `DELIVERED`，或明确进入 `REDO_PENDING`/`HUMAN_INTERVENTION`；每次转移有不可变事件记录。
6. **验证门禁有效**：编码任务必须有自动命令、退出码和关键输出；任一关键检查失败不得交付。非编码任务必须有人工检查记录和用户反馈状态。
7. **兜底有限且可审计**：失败后只向同一引擎重做一次，重做请求包含不满意原因；第二次失败自动停止并转人工介入。
8. **命令可复现**：在 Windows Git Bash 中可按模板复现三类调用，日志、差异和验证报告能按 `task_id` 定位。

---

## 6. 双域路由补充（2026-08-08 定稿增补）

> 本协议 v2 主体覆盖**开发域**。日常域任务按本节约束路由，权威来源为
> `docs/plans/ORCHESTRATION-BOUNDARIES.md` §0。

### 6.1 域判断

任务进来先判断是否涉及项目代码/仓库改动：是 → 开发域（走第 1~5 章）；否 → 日常域。

### 6.2 日常域路由

| 类型 | 处理 | 引擎 |
|---|---|---|
| 事务型（查资料/总结/问答/整理/消息） | Hermes 直办 | Hermes |
| 内容型（文档/周报/PPT/表格） | Hermes + 对应技能 | Hermes |
| 研究型（深度调研/方案对比/流程设计） | Hermes 先干 → 干不好或用户要求 → 升级 Codex sol | Hermes → Codex sol（懒升级） |
| 自动化型（定时/监控/日报） | Hermes cron/gateway | Hermes |
| 编码型 | 转开发域 | — |

### 6.3 跨域引擎边界

- Hermes：全域主力。
- Codex sol：开发域 L3 + 日常域研究型（懒升级触发）。
- Claude：**仅开发域 L2**，日常域永不出现（Claude 只写代码）。
- 日常域研究型升级 Codex sol 时，复用 §3.1 命令模板（`codex exec --model gpt-5.6-sol --sandbox danger-full-access`），产出物仍是可交付文档，不走编码流水线。
