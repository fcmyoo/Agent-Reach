# 任务定义单（Task Definition）— 多引擎流水线第 0 阶段

> 启动任何任务前，先填这张单。**未定义清楚的任务不允许进入拆解/规划阶段。**
> 由 Hermes 与用户对齐后填写，存入 `artifacts/<task-id>/request.md`，作为后续所有阶段（拆解 → 方案 → 执行 → 验证）的唯一事实来源。

---

## 1. 目标（Goal）

<!-- 一句话：这个任务要达成什么可观察的结果。写不出这句话 = 任务未定义。 -->

> 例：给 agent-reach 增加 `stats` 子命令，统计各渠道 30 天内调用次数并输出表格。

## 2. 背景与动机（Context）

<!-- 为什么现在做？关联什么现状/问题/需求？给执行者足够的上下文。 -->

> 例：CLI 已有 check-update/watch 等命令，用户想了解渠道使用分布；数据源为 ~/.agent-reach/ 下的调用日志。

## 3. 范围（Scope — Do）

<!-- 明确列出要做的事，颗粒度到可验收。 -->

- [ ] 子项 1
- [ ] 子项 2

## 4. 不做（Non-Goals）

<!-- 明确排除，防止执行者越权扩范围。 -->

> 例：不做数据可视化、不做跨设备同步、不改现有命令行为。

## 5. 验收标准（Acceptance Criteria）

<!-- 可验证的完成定义。每条都应能通过命令/测试/人工检查判定。 -->

- [ ] `agent-reach stats` 输出表格，包含 8+ 渠道行
- [ ] 无日志时输出空表并退出 0
- [ ] `uv run pytest` 全量通过（571 passed）
- [ ] 新增对应单元测试

## 6. 约束与偏好（Constraints）

<!-- 技术栈、成本、模型、风格等硬性约束。 -->

> 例：Python 3.11；遵循 pyproject.toml 现有依赖；输出格式参考 `doctor --json`；中英文提示均需支持。

## 7. 风险与开放问题（Risks / Open Questions）

<!-- 不确定的、需要任务中探索的。 -->

- [ ] 调用日志格式是否稳定？需要先读代码确认。

---

## 填写完成后，进入标准流程

```
第 0 阶段  任务定义（本单）          ← Hermes + 用户对齐
第 1 阶段  Hermes 拆解 + 收集上下文   → artifacts/<task-id>/context.md（读代码/Agent-Reach/opencli 取数）
第 2 阶段  Codex (gpt-5.6-sol) 出方案 → docs/plans/<task>-plan.md（含验收标准与命令模板）
第 3 阶段  Claude 按方案执行          → 严格按 plan，max-turns 40
第 4 阶段  验证与汇报                → pytest / test.sh / git diff 审查 → 结果回填
```

**原则**：任务定义不清 → 先问清楚，不猜；方案未冻结 → 不派 Claude；验证未过 → 不报完成。
