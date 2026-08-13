# Hermes + Codex CLI + Claude Code 多引擎协作落地方案

## 0. 目标与边界

本文定义一套可运行、可观测、可回退的多引擎 AI 协作架构。权威分工如下：

- **Hermes（Nous Research AI agent 框架）**：负责接收需求、拆解和分配任务、读取代码、通过工具查资料、整理上下文和路由；不承担深度推理和最终编码。
- **Codex CLI（gpt-5.6-sol）**：负责详细规划、架构设计、风险分析、验收标准和方案输出；不直接改代码。
- **Claude Code**：按 Hermes 转交的详细方案/plan 执行指定编码任务；不重新设计方案，不越权扩大范围。
- **验证环节**：由 Hermes 调度自动化检查和人工确认，确认代码、测试、文档及交付物一致后再汇报。

核心闭环为：**用户表达需求 → Hermes 拆解/分配 → Codex 出详细方案 → Claude 按方案执行 → 验证 → 汇报**。

## 1. 架构总览

### 1.1 ASCII 架构图

```text
                              控制面（任务、状态、预算）
┌────────┐  需求/约束  ┌──────────────────────────────────────────────┐
│ 用户   │────────────▶│ Hermes Orchestrator                         │
└────────┘             │ - 任务拆解、路由、上下文封装                 │
     ▲                 │ - 读取代码、资料采集、状态机、汇报           │
     │                 └──────────────┬───────────────────────────────┘
     │                                │
     │                                │ 规划请求（只读上下文 + 验收目标）
     │                                ▼
     │                 ┌────────────────────────┐
     │                 │ Codex CLI              │
     │                 │ gpt-5.6-sol            │
     │                 │ 深度规划/方案/风险      │
     │                 └────────────┬───────────┘
     │                              │ PLAN_READY（plan.md + manifest）
     │                              ▼
     │                 ┌────────────────────────┐
     │                 │ Claude Code            │
     │                 │ 按 plan 执行编码        │
     │                 │ Read/Edit/Write/Bash   │
     │                 └────────────┬───────────┘
     │                              │ 代码、测试、变更摘要
     │                              ▼
     │                 ┌────────────────────────┐
     │                 │ Hermes 验证与交付       │
     │                 │ 测试/审查/回归/汇报      │
     │                 └────────────┬───────────┘
     │                              │ DONE / BLOCKED
     └──────────────────────────────┘

                              数据面（外部信息）
      ┌──────────────┐   ┌──────────────┐   ┌──────────────┐
      │ Agent-Reach  │   │ opencli      │   │ SearXNG      │
      │ doctor/API   │   │ browser/auth │   │ 搜索/网页     │
      └──────┬───────┘   └──────┬───────┘   └──────┬───────┘
             │                  │                  │
             └──────────┬───────┴──────────┬───────┘
                        ▼                  ▼
                 ┌──────────────┐   ┌──────────────┐
                 │ yt-dlp       │   │ 本地仓库/日志  │
                 │ 视频元数据/字幕│   │ artifacts/    │
                 └──────────────┘   └──────────────┘
```

### 1.2 职责边界与数据流

1. Hermes 是唯一的编排入口，维护任务 ID、状态、预算和交付记录。它把需求转换为两个明确的请求：`PLAN_REQUEST` 和 `EXEC_REQUEST`。
2. Codex 只接收完成规划所需的只读上下文，产出可执行的 `plan.md`、文件清单、测试命令、风险和回退步骤。Codex 不应写入业务代码。
3. Claude 只接收冻结版本的 plan 和允许修改的文件范围，执行 `Read/Edit/Write/Bash`。Claude 的输出包括变更、测试结果和未完成项。
4. 工具链只产生带来源的资料：URL、抓取时间、摘要、哈希或原始文件位置写入 `artifacts/<task-id>/sources.json`。资料先进入 Hermes，再按需放入 Codex 规划上下文；不把未经核验的网页内容直接当作事实。
5. 验证结果是独立事件 `VERIFY_REPORT`，必须引用实际命令和退出码。只有验证通过，Hermes 才能向用户报告完成。

## 2. 角色分工矩阵

| 引擎/组件 | 负责什么 | 明确不做什么 | 何时启用 | 适用任务类型 |
| --- | --- | --- | --- | --- |
| Hermes | 接收需求、拆解任务、读取仓库、收集资料、生成上下文包、调用 Codex/Claude、维护状态和预算、汇报 | 不做深度架构推理；不直接大规模改代码；不替代测试结论 | 每个任务开始、阶段切换、异常恢复和最终汇报 | 路由型、资料型、协调型、验证编排型 |
| Codex CLI / gpt-5.6-sol | 设计方案、权衡架构、定义接口、列出文件级步骤、测试策略、风险和验收标准 | 不执行编码；不擅自调用 Claude；不把猜测写成已验证事实 | 需求有多文件影响、架构选择、风险高或验收复杂时 | 规划型、设计型、疑难问题分析型 |
| Claude Code | 严格依照 plan 修改代码、运行指定测试、提交变更摘要 | 不重写需求、不改变架构方向、不扩大文件范围；遇到方案缺口先标记而非自行发散 | `PLAN_READY` 且执行范围、验收标准明确时 | 执行型、重构型、测试补齐型、文档实现型 |
| Agent-Reach | 探测和调用可用后端（社媒、网页、代码资料等），返回结构化数据 | 不做最终判断；不绕过认证策略 | 需要外部资料或后端健康检查时 | 资料获取型 |
| opencli | 打开/读取网页、检查登录态、进行浏览器自动化 | 不作为长期状态库；不泄露认证信息 | 需要登录页面、动态页面或浏览器状态时 | 网页读取型、认证型 |
| SearXNG | 聚合搜索候选来源 | 不保证来源真实性；不替代原文核验 | 需要发现资料、定位官方文档时 | 搜索型 |
| yt-dlp | 获取视频元数据、字幕或指定媒体资源 | 不下载超出任务范围的内容；不替代版权/权限判断 | 任务依赖视频教程、演讲或字幕时 | 视频资料型 |

## 3. 任务流转协议

### 3.1 任务对象与状态机

每个任务生成稳定的 `task_id`，建议使用 `YYYYMMDD-HHMM-短名-序号`。最小任务对象如下：

```yaml
task_id: 20260808-1030-cache-01
request: "用户原始需求"
class: planning | execution | verification
scope:
  repo: "D:/code/github/Agent-Reach"
  allowed_paths: []
  forbidden_paths: []
budget:
  codex_turns: 1
  claude_max_turns: 8
  time_minutes: 30
artifacts:
  context: artifacts/<task_id>/context.md
  plan: artifacts/<task_id>/plan.md
  sources: artifacts/<task_id>/sources.json
  verify: artifacts/<task_id>/verify.md
```

状态机：

```text
REQUESTED
   │ Hermes 补齐目标、范围、约束
   ▼
TRIAGED ──资料不足──▶ RESEARCHING ──资料齐全──▶ TRIAGED
   │
   ├─简单执行且已有明确 plan ───────────────▶ EXEC_READY
   ├─需要设计/权衡 ─▶ PLANNING ─▶ PLAN_READY
   └─已有改动待检查 ─────────────────────────▶ VERIFYING

EXEC_READY / PLAN_READY
   │ Hermes 固化上下文、预算、允许路径
   ▼
EXECUTING ──达到 max-turns/失败──▶ PARTIAL
   │                                     │
   │ 测试/静态检查完成                     └─复盘后 REPLAN 或人工接管
   ▼
VERIFYING ──通过──▶ DELIVERED
      │
      └─失败/方案与实现不符──▶ REPLAN ─▶ PLANNING
```

每次状态变更追加不可变事件日志 `events.jsonl`，至少包含 `timestamp`、`task_id`、`from`、`to`、`actor`、`command`、`exit_code`、`artifact_paths`。

### 3.2 任务分类与路由规则

| 分类 | 判定条件 | 路由 | 交付门槛 |
| --- | --- | --- | --- |
| 规划型 | 涉及架构选择、跨模块改动、未知技术、风险高，或用户明确要求方案 | Hermes → 工具调研 → Codex → `PLAN_READY`；默认不调用 Claude | plan 包含目标、非目标、文件级步骤、接口、测试、风险、回退、预算 |
| 执行型 | 已有批准的 plan，文件范围和验收命令明确 | Hermes → Claude；必要时先做轻量资料核验 | Claude 变更与 plan 对齐；指定测试通过；产出 diff 摘要 |
| 验证型 | 已有实现，需要测试、审查、回归或对比验收 | Hermes → 运行测试/静态检查 → 生成 `VERIFY_REPORT`；发现设计缺陷再转 Codex | 每项验收标准都有证据（命令、退出码、关键输出）；无阻塞缺陷 |

路由判据：单文件、机械、已有测试且无设计决策的任务可直接执行；一旦 Claude 需要自行选择 API、数据模型、并发或安全策略，必须退回规划型。

### 3.3 方案与执行的交接协议

Codex 产出的 `plan.md` 固定包含：

1. `Objective`、`Non-goals`、假设和依赖；
2. 受影响文件列表及每个文件的修改意图；
3. 数据流、接口契约、错误处理和兼容性要求；
4. 可复制的测试/验证命令及预期结果；
5. 风险、回退点、未决问题和预算。

Hermes 在转交 Claude 前生成 `EXEC_REQUEST`，把 plan 内容哈希、允许路径、禁止路径和验收命令写入请求。Claude 返回后，Hermes 比对文件变更和哈希，禁止“无计划文件”变更，除非重新规划并记录批准。

## 4. 引擎调用命令模板

以下命令均在仓库根目录执行。Windows PowerShell 中，复杂提示词建议使用 here-string，避免引号转义导致任务内容损坏。

### 4.1 Hermes 侧调用 Codex

标准命令（必须使用 `danger-full-access`）：

```powershell
codex exec --sandbox danger-full-access --model gpt-5.6-sol '<规划任务>'
```

推荐封装：

```powershell
$planPrompt = @'
你是规划引擎。只输出可执行方案，不修改代码。
任务 ID：20260808-1030-cache-01
用户需求：<原始需求>
仓库范围：D:\code\github\Agent-Reach
已收集资料：<sources.json 摘要>
请输出：目标/非目标、假设、文件级步骤、接口契约、测试命令、风险、回退、验收标准。
'@
codex exec --sandbox danger-full-access --model gpt-5.6-sol $planPrompt 2>&1 |
  Tee-Object -FilePath artifacts\20260808-1030-cache-01\codex.log
```

**Windows 约束**：workspace-write 沙箱存在 DPAPI bug，可能导致 Codex 无法正常访问工作区；本架构统一使用 `--sandbox danger-full-access`。Hermes 仍通过 `allowed_paths`、任务工作目录、版本控制和审计日志限制业务范围，而不是依赖该沙箱模式。

调用参数建议：

- 一次请求只解决一个规划问题；把仓库摘要、目标文件和资料清单放入上下文，避免发送整个仓库。
- 规划型任务默认只调用一次 Codex；方案不完整时携带缺口清单再次调用，而不是盲目重试。
- 记录 stdout/stderr、退出码、模型、开始/结束时间和输入摘要哈希。

### 4.2 Hermes 侧调用 Claude

标准 print 模式命令：

```powershell
claude -p '<执行任务>' --allowedTools 'Read,Edit,Write,Bash' --max-turns N
```

推荐封装：

```powershell
$execPrompt = @'
执行任务 ID：20260808-1030-cache-01
严格依据 artifacts/20260808-1030-cache-01/plan.md 实施。
允许修改：agent_reach/**、tests/**、docs/**（仅列出的文件）
禁止：改变架构目标、修改密钥/CI 配置、引入未批准依赖。
完成后运行：<plan 中的测试命令>
最终输出：修改文件、测试结果、未完成项、建议回退点。
'@
claude -p $execPrompt --allowedTools 'Read,Edit,Write,Bash' --max-turns 8 2>&1 |
  Tee-Object -FilePath artifacts\20260808-1030-cache-01\claude.log
$claudeExit = $LASTEXITCODE
git status --short
git diff --stat
```

print 模式免交互，适合 Hermes 的非交互编排。已知坑是：撞到 `--max-turns` 时，改动可能已经落盘，但进程会以非零退出。Hermes 必须先检查 `git status`、`git diff` 和测试结果，再决定续跑、缩小任务或回滚；不能仅按退出码判定“没有改动”。

### 4.3 `--max-turns` 与成本控制

| 场景 | 建议 `--max-turns` | 说明 |
| --- | ---: | --- |
| 单文件机械修改 | 4 | plan 清晰、测试简单；超出即暂停复盘 |
| 中等功能（2～8 个文件） | 8 | 默认值，覆盖实现和一次修正 |
| 跨模块重构/测试迁移 | 12 | 先拆成多个任务；只有确有必要才使用 |
| 调试或不确定性高 | 6 + 重新规划 | 不用无限加 turns，先把新事实反馈 Codex |

成本闸门：

1. Hermes 在 `TRIAGED` 阶段估算文件数、预计 turns、外部调用次数和时间上限；超过阈值必须人工确认。
2. 默认“先规划后执行”，避免 Claude 在不明确目标下反复试错；Claude 每轮都复用同一 plan 和测试命令。
3. 将低价值日志、重复网页、完整二进制和无关目录排除出上下文；来源先摘要，原文按需读取。
4. 维护每日/每任务预算计数器。达到 80% 发出告警，达到 100% 停止新调用并进入 `BLOCKED` 或人工审批。
5. 低风险、模板化、已有测试覆盖的规划可降级到低阶模型；高风险设计、公共 API、安全/数据迁移仍固定使用 gpt-5.6-sol。

## 5. 数据获取工具链接入

### 5.1 统一资料采集流程

```text
Hermes 发现资料需求
  → agent-reach doctor --json（后端健康探测）
  → 选择 SearXNG / opencli / Agent-Reach 后端
  → 抓取原文/元数据/字幕
  → 去重、标记来源和时间
  → sources.json + context.md
  → Codex 仅消费带来源上下文
```

每条来源至少记录：`source_id`、`kind`、`url`、`title`、`retrieved_at`、`backend`、`auth_required`、`content_hash`、`summary`、`local_path` 和 `trust`（官方/二手/待核验）。

### 5.2 Agent-Reach

任务开始或后端异常时运行：

```powershell
agent-reach doctor --json
```

Hermes 解析 JSON，检查后端是否 `ready`、需要哪些认证、失败原因和建议修复。只有 `ready` 的后端进入路由；失败后切换 SearXNG 或 opencli，并将降级原因写入事件日志。不要把 token、cookie 或完整认证响应写入 `sources.json`。

### 5.3 opencli

浏览器型资料按“打开 → 读取 → 记录 URL/标题/时间 → 关闭或复用会话”的顺序执行。示例模板（具体子命令以本机 `opencli --help` 为准）：

```powershell
opencli browser open '<URL>'
opencli browser read
opencli auth status
```

`auth status` 只用于判断会话是否存在，不把凭据复制到 prompt。动态页面读取失败时保存页面快照或关键文本，并在 `sources.json` 标记“可能受登录态/脚本影响”。

### 5.4 SearXNG

优先搜索官方文档、源码仓库和版本公告，再用第二来源交叉验证。Hermes 将查询词、返回链接和筛选条件记录下来；Codex 需要引用时使用 `source_id`，不直接引用无 URL 的模型记忆。

### 5.5 yt-dlp

当方案依赖视频教程、会议录像或字幕时，只采集完成任务所需的元数据/字幕：

```powershell
yt-dlp --dump-single-json '<视频 URL>'
yt-dlp --write-auto-subs --sub-langs 'zh.*,en.*' --skip-download '<视频 URL>'
```

输出经去重和摘要后放入 `artifacts/<task-id>/sources/`；大文件和无关媒体不进入 Codex/Claude 上下文。

## 6. 模型与成本策略

### 6.1 默认策略

- **gpt-5.6-sol**：规划、架构权衡、复杂调试策略、跨模块影响分析、最终验收设计。一次高质量 plan 通常比 Claude 多轮试错更省成本。
- **Claude API**：执行已批准的 plan、代码修改、测试和局部修复。通过 `--max-turns`、允许工具白名单和文件范围控制消耗。
- **低阶模型（可选）**：仅处理格式化、简单重命名、已有测试的机械变更、资料去重和摘要。低阶模型不得决定公共 API、权限边界、数据迁移或安全策略。

### 6.2 降级判定

满足以下条件才允许降级：影响范围 ≤ 2 个文件、无新依赖、无公共接口/数据格式变化、测试命令已存在且稳定、失败可快速回滚。任一条件不满足，继续使用 gpt-5.6-sol 规划或人工审批。

### 6.3 预算与计量

每个任务记录：Codex 调用次数/输入输出 token（若可得）、Claude turns、工具调用次数、墙钟时间和估算费用。按项目设置硬上限；预算耗尽时保留现有工件，状态转 `BLOCKED_BUDGET`，等待用户批准，不自动重试。

## 7. 风险与兜底清单

| 风险 | 触发信号 | 兜底动作 | 预防措施 |
| --- | --- | --- | --- |
| Claude `max-turns` 中断 | 非零退出、输出含达到 turns | 先 `git status/diff`；若变更完整则直接验证；否则用差异摘要续跑或回退到 plan | 按任务复杂度设 4/8/12；每轮有明确终点 |
| Codex 沙箱 DPAPI 问题 | workspace-write 无法访问工作区/凭据错误 | 统一改用 `--sandbox danger-full-access`，依靠路径白名单和审计控制范围 | Windows 启动自检并记录模式 |
| 方案与执行脱节 | 变更文件不在 plan、接口/测试不一致 | 阻断交付，生成差异报告，回到 `REPLAN`；禁止 Claude 自行扩大范围 | plan 哈希、允许路径、变更比对 |
| 上下文隔离失效 | 敏感信息进入 prompt、跨任务污染 | 使用 task-id 独立目录、来源脱敏、最小上下文；必要时清空会话后重启 | context manifest、密钥扫描、日志脱敏 |
| 成本失控 | turns/工具调用/时间超预算 | 80% 告警，100% 熔断；保留工件并人工审批 | 预算闸门、分解大任务、低阶模型仅用于低风险子任务 |
| 外部资料失真或过期 | 来源非官方、时间过旧、互相矛盾 | 标记待核验，至少一条官方来源；无法核验则在 plan 列为风险 | `sources.json` 信任级别和抓取时间 |
| 测试环境不可用 | 依赖缺失、网络或凭据失败 | 区分“代码失败”和“环境失败”，给出复现命令；不得宣称通过 | 在 plan 中声明环境前置条件 |

通用回退原则：保留 `plan.md`、日志、diff 和验证报告；任何自动回退都必须是可逆的（优先使用版本控制分支/补丁），并将原因写入事件日志。

## 8. 分阶段落地路线图

### Phase 1：最小闭环

范围：单仓库、单用户、单任务串行执行；Hermes 手工或脚本化编排 Codex 与 Claude；工具先接 Agent-Reach doctor、SearXNG 和基础 opencli。

实施项：

1. 建立 `artifacts/<task-id>/` 目录约定、`events.jsonl` 和 `sources.json` schema。
2. 实现三个命令包装器：`run-codex-plan`、`run-claude-exec`、`run-verify`，统一记录 stdout/stderr、退出码和耗时。
3. 固化 `PLAN_REQUEST`、`EXEC_REQUEST`、`VERIFY_REPORT` 模板及状态机。
4. 在 Windows 启动检查中强制 `--sandbox danger-full-access`；Claude 默认 `--max-turns 8`。
5. 用一个低风险真实任务跑通：需求、plan、代码变更、测试和汇报均可追溯。

验收标准：

- 从用户需求到 `DELIVERED` 的状态链完整，无人工复制粘贴关键字段。
- Codex 输出的 plan 可被 Claude 直接执行，变更文件均在允许列表内。
- Claude 即使因 max-turns 非零退出，也能被脚本发现已落盘变更并进入验证。
- 至少一种外部来源带 `source_id`、URL、时间和摘要进入 plan。
- 每个任务可在 5 分钟内定位：调用命令、日志、diff、测试结果和费用估算。

### Phase 2：扩展与治理

范围：并行任务、更多 Agent-Reach 后端、自动重试/重规划、权限与成本治理、持续集成。

实施项：

1. 为 Hermes 增加队列和并发配额；按仓库/任务锁避免 Claude 同时修改同一文件。
2. 接入 yt-dlp、更多 opencli 浏览器动作和来源去重；建立资料缓存及过期策略。
3. 增加 plan 哈希校验、敏感信息扫描、依赖变更审批和自动 diff 审查。
4. 将测试、lint、类型检查、构建和安全扫描注册为可配置验证器；生成统一 `VERIFY_REPORT`。
5. 建立预算仪表盘、按模型成本报表、失败率、平均 turns、重规划率和交付周期指标。
6. 为 `PARTIAL`、`BLOCKED`、`REPLAN` 设计人工接管界面或 CLI，支持从已有工件恢复，而不是从头运行。

验收标准：

- 并行任务不会产生未授权的跨任务文件修改或上下文泄露。
- 预算、权限、来源和变更审计可按 `task_id` 查询并导出。
- 自动验证能区分代码失败、环境失败、资料不足和方案缺陷，并路由到正确引擎。
- 至少连续 20 个任务的成功率、成本和回退数据可复盘；关键指标达到项目设定阈值后才扩大并发。

## 9. 推荐的交付目录

```text
artifacts/<task-id>/
├── request.md       # 用户原始需求与约束
├── context.md       # Hermes 整理后的最小上下文
├── sources.json     # 外部资料来源清单
├── plan.md          # Codex 方案（冻结版本）
├── exec-request.md  # 发给 Claude 的执行请求
├── codex.log
├── claude.log
├── diff.patch
├── verify.md        # 命令、退出码、关键输出
└── events.jsonl     # 状态和审计事件
```

最终汇报只引用 `verify.md` 和 `diff.patch` 的事实，并明确列出未完成项、环境限制、剩余风险和下一步；不得把模型的推测写成已验证结果。
