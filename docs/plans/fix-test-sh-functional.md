# test.sh 功能测试段修复实施方案

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans (recommended) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 test.sh 中调用不存在的 read/search* 子命令的 14 项测试替换为当前 agent-reach CLI 的真实、快速、无凭据冒烟测试。

**Architecture:** 保留现有 test_it 的 PASS/FAIL/SKIP 汇总和逐项输出，在其上增加“期望输出正则”参数；每条新测试先匹配自己的语义关键词，再使用统一的环境缺失/网络不可用关键词判定 SKIP。功能段不调用需要 Cookie、API key、浏览器会话或长时间下载的上游工具。

**Tech Stack:** Bash/Git Bash、GNU grep -E、GNU timeout、agent-reach argparse CLI。

---

## 1. 当前 CLI 事实

agent_reach/cli.py 注册且分发的子命令只有：

| 命令 | 参数/副作用 | 稳定输出特征 |
|---|---|---|
| setup | 交互式配置，会询问输入 | Agent Reach Setup、配置提示；不适合自动功能段 |
| install | 安装系统依赖、渠道和 skill；已有安装段会调用 | Agent Reach Installer、Environment:、渠道状态报告、安装完成；功能段只测 --help |
| configure | 写入 proxy/token/cookie，或 --from-browser 读取浏览器 | 成功时 configured/✅，缺参数会 argparse usage；功能段只测 --help |
| doctor | 检查所有 channel；文本模式还以 force=False 自动补装 skill；--json 无 skill 写入 | 文本含 Agent Reach 状态、图例 [!]/[X]、状态：N/M 个渠道可用；JSON 每项含 status/name/message/tier/backends/active_backend |
| uninstall | 删除 Agent Reach 配置和 skill；--dry-run 仅预览 | Dry run complete. No changes were made. 或 Nothing to remove；功能段只测 --help |
| skill | 必须二选一 --install/--uninstall，写/删 skill 文件 | usage 显示 --install、--uninstall；功能段只测 --help |
| format | 必须平台 xhs，从 stdin 读 JSON 后输出清洗后的 JSON | format --help 显示 {xhs}；printf '{}' | agent-reach format xhs 输出 JSON {} |
| transcribe | 必须 source；调用 Groq/OpenAI Whisper，可能需要 key/网络 | transcribe --help 显示 source、--provider、-o/--output；真实转录不放入功能段 |
| check-update | 请求 GitHub release/commit，最多 3 次重试，网络差时可达约几十秒 | 先输出 当前版本: v...，成功为 ✅ 已是最新版本/最新版本:/最新提交:，失败为 [!] 无法检查更新（...） |
| watch | channel 健康检查 + update 检查，可能网络慢 | 正常为 Agent Reach: 全部正常 (N/M ... v...)，有问题为监控报告并含 [!]/[X]；功能段只测 --help |
| version | 纯本地版本输出 | Agent Reach vX.Y.Z |

全局选项 `-h/--help` 输出 argparse usage，`-v/--verbose` 打开 loguru INFO 日志，`--version` 直接输出同样的 `Agent Reach vX.Y.Z`。

README 明确将 Agent Reach 定位为“选择、安装、体检、路由”的能力层，实际读取和搜索由 Agent 直接调用 curl/Jina Reader、gh、yt-dlp、bili、mcporter、feedparser 等上游工具完成。因此 agent-reach read、search、search-github、search-twitter、search-reddit、search-youtube、search-bilibili、search-xhs 不是当前 CLI 的兼容别名，不能继续出现在功能段。

### doctor 的未配置环境判断

doctor.py::format_report 不输出 ⚠️，而是 Rich markup [yellow][!][/yellow] 和 [red][X][/red]；channel 消息使用中文 未安装、未配置、未登录、未认证、需要配置 等。即使全部可选渠道不可用，报告仍会生成 Agent Reach 状态 和 状态：N/M 个渠道可用；此外 Web channel 的健康提示含 https://r.jina.ai/URL。所以原先“看到 http 就 PASS”的通用规则会掩盖 doctor 的坏状态，必须让每项先匹配自身期望关键词，并扩展 SKIP 关键词。

## 2. 新的 14 项功能测试清单

以下表格中的“期望”作为 grep -Eq 正则；命令均在 venv 激活后的 agent-reach 上执行。

| 分段/名称 | 命令 | 期望输出特征 | 判定 |
|---|---|---|---|
| 📖 CLI 诊断 | agent-reach doctor | Agent Reach 状态 或 状态：.../[0-9]+ 个渠道可用 | 命中即 PASS；命令产生报告但某渠道 [!]/[X] 不算失败。 |
| 📖 CLI 诊断帮助 | agent-reach doctor --help | usage: agent-reach doctor、--json | 命中即 PASS。 |
| 📖 转录命令存在性 | agent-reach transcribe --help | usage: agent-reach transcribe、source、--provider | 命中即 PASS，不调用 Whisper。 |
| 📖 格式命令帮助 | agent-reach format --help | usage: agent-reach format、{xhs} | 命中即 PASS。 |
| 📖 格式 handler 冒烟 | printf '%s\n' '{}' \| agent-reach format xhs | 以 { 开头的 JSON 输出（^\{） | 命中即 PASS；Error: no input/invalid JSON 为 FAIL。 |
| 📖 skill 命令帮助 | agent-reach skill --help | usage: agent-reach skill、--install、--uninstall | 命中即 PASS，不写入 skill。 |
| 📖 版本 | agent-reach version | Agent Reach v[0-9]+\.[0-9]+\.[0-9]+ | 命中即 PASS。 |
| 🔍 更新检查 | timeout 15s agent-reach check-update \|\| printf '%s\n' '__CHECK_UPDATE_TIMEOUT__' | 成功：已是最新版本、最新版本: 或最新提交: | 成功特征 PASS；无法检查更新、DNS/连接/速率限制、__CHECK_UPDATE_TIMEOUT__ 为 SKIP；其他（含 usage）FAIL。 |
| 🔍 更新命令帮助 | agent-reach check-update --help | usage: agent-reach check-update | 命中即 PASS；不访问 GitHub。 |
| 🔍 watch 命令帮助 | agent-reach watch --help | usage: agent-reach watch、scheduled tasks | 命中即 PASS；不执行健康检查。 |
| 🔍 setup 命令帮助 | agent-reach setup --help | usage: agent-reach setup、Interactive configuration wizard | 命中即 PASS，不进入交互。 |
| 🔍 install 参数帮助 | agent-reach install --help | usage: agent-reach install、--dry-run、--safe | 命中即 PASS，不重复安装。 |
| 🔍 configure 参数帮助 | agent-reach configure --help | usage: agent-reach configure、--from-browser | 命中即 PASS，不写配置。 |
| 🔍 uninstall 参数帮助 | agent-reach uninstall --help | usage: agent-reach uninstall、--dry-run | 命中即 PASS，不删除数据。 |

统一 SKIP 正则建议为：

~~~~text
⚠️|not installed|not configured|\[!\]|\[X\]|未安装|未配置|未认证|未登录|需要配置|需要登录|无法检查更新|超时|timeout|DNS|连接失败|速率限制|__CHECK_UPDATE_TIMEOUT__
~~~~

其中 [!]/[X] 是 doctor/watch 的实际 Rich 文本；无法检查更新 等只对更新检查降级为环境跳过。不要把通用 http 放入 SKIP；它只应作为旧默认 PASS 标记，且必须在期望正则之后判断。

## 3. 精确 diff 建议

实现时先把 test_it 改为接受 name command expected [skip_pattern]，保留旧 PASS 标记作为无第三参数时的默认值。该小改动是必要的，否则 version/--help 的正确输出不含 📖、🔗 或 http 会被误判 FAIL。

~~~~diff
@@
 test_it() {
     local name="$1"
-    shift
+    local command="$2"
+    local expected="${3:-📖|🔗|http}"
+    local skip_pattern="${4:-⚠️|not installed|not configured|\\[!\\]|\\[X\\]|未安装|未配置|未认证|未登录|需要配置|需要登录|无法检查更新|超时|timeout|DNS|连接失败|速率限制|__CHECK_UPDATE_TIMEOUT__}"
     echo -n "  $name ... "
-    output=$(eval "$@" 2>&1) || true
-    if echo "$output" | grep -q "📖\\|🔗\\|http"; then
+    output=$(eval "$command" 2>&1) || true
+    if printf '%s\n' "$output" | grep -Eq "$expected"; then
         echo "✅"
         PASS=$((PASS+1))
-    elif echo "$output" | grep -q "⚠️\\|not installed\\|not configured"; then
+    elif printf '%s\n' "$output" | grep -Eq "$skip_pattern"; then
~~~~

然后将 test.sh 当前从 echo “📖 阅读测试” 到最后一个 search-xhs 测试的两个段落替换为：

~~~~diff
-echo "📖 阅读测试"
-test_it "网页" "agent-reach read 'https://example.com'"
-test_it "GitHub" "agent-reach read 'https://github.com/fcmyoo/Agent-Reach'"
-test_it "YouTube" "agent-reach read 'https://www.youtube.com/watch?v=dQw4w9WgXcQ'"
-test_it "B站" "agent-reach read 'https://www.bilibili.com/video/BV1d4411N7zD'"
-test_it "RSS" "agent-reach read 'https://hnrss.org/frontpage'"
-test_it "Twitter" "agent-reach read 'https://x.com/elonmusk/status/1893797839927353448'"
-test_it "Reddit" "agent-reach read 'https://www.reddit.com/r/LocalLLaMA/hot'"
+echo "📖 CLI 诊断与命令测试"
+test_it "doctor 渠道状态" "agent-reach doctor" "Agent Reach 状态|状态：.*[0-9]+/[0-9]+"
+test_it "doctor 帮助" "agent-reach doctor --help" "usage: agent-reach doctor|--json"
+test_it "transcribe 帮助" "agent-reach transcribe --help" "usage: agent-reach transcribe|source|--provider"
+test_it "format 帮助" "agent-reach format --help" "usage: agent-reach format|\\{xhs\\}"
+test_it "format xhs handler" "printf '%s\n' '{}' | agent-reach format xhs" "^\\{" "Error: no input|invalid JSON"
+test_it "skill 帮助" "agent-reach skill --help" "usage: agent-reach skill|--install|--uninstall"
+test_it "version" "agent-reach version" "^Agent Reach v[0-9]+\\.[0-9]+\\.[0-9]+"

 echo ""
-echo "🔍 搜索测试"
-test_it "全网搜索" "agent-reach search 'best AI agent framework' -n 2"
-test_it "GitHub搜索" "agent-reach search-github 'yt-dlp' -n 2"
-test_it "Twitter搜索" "agent-reach search-twitter 'AI agent' -n 2"
-test_it "Reddit搜索" "agent-reach search-reddit 'machine learning' -n 2"
-test_it "YouTube搜索" "agent-reach search-youtube 'AI tutorial' -n 2"
-test_it "B站搜索" "agent-reach search-bilibili 'AI' -n 2"
-test_it "小红书搜索" "agent-reach search-xhs 'AI' -n 2"
+echo "🔍 CLI 更新与参数测试"
+test_it "check-update" "timeout 15s agent-reach check-update || printf '%s\n' '__CHECK_UPDATE_TIMEOUT__'" "已是最新版本|最新版本:|最新提交:"
+test_it "check-update 帮助" "agent-reach check-update --help" "usage: agent-reach check-update"
+test_it "watch 帮助" "agent-reach watch --help" "usage: agent-reach watch|scheduled tasks"
+test_it "setup 帮助" "agent-reach setup --help" "usage: agent-reach setup|Interactive configuration wizard"
+test_it "install 参数帮助" "agent-reach install --help" "usage: agent-reach install|--dry-run|--safe"
+test_it "configure 参数帮助" "agent-reach configure --help" "usage: agent-reach configure|--from-browser"
+test_it "uninstall 参数帮助" "agent-reach uninstall --help" "usage: agent-reach uninstall|--dry-run"
~~~~

> 若执行者不希望改动 test_it 函数，可将每个命令包装成“匹配期望后输出 http”的 shell 管道，但这种写法会隐藏实际关键词，故不推荐；上述可选正则参数更直接且仍复用同一 PASS/SKIP 计数框架。

## 4. 实施步骤与验证

- [ ] **Step 1: 更新判定函数。** 仅修改 test.sh 的 test_it，加入期望/跳过正则参数；默认 PASS 仍兼容 📖|🔗|http，并新增 doctor 的 [!]、[X] 和中文配置缺失词。
- [ ] **Step 2: 替换两个功能测试段。** 删除所有 read、search* 调用，按上面的 14 条命令和正则逐条写入；保留 PASS/FAIL/SKIP 汇总和 FAIL=0 的退出策略。
- [ ] **Step 3: 做静态检查。** 在 Git Bash 执行 bash -n test.sh；预期无输出且退出码为 0。执行 rg -n 'agent-reach (read|search|search-)' test.sh；预期无匹配。
- [ ] **Step 4: 做快速 CLI 冒烟。** 在仓库根目录执行 agent-reach version、agent-reach doctor --help、agent-reach transcribe --help、printf '{}' | agent-reach format xhs、agent-reach skill --help；预期分别命中版本号、usage、source/provider、{}、install/uninstall。
- [ ] **Step 5: Windows Git Bash 验收。** 执行 bash test.sh。安装段完成后，功能段应打印 14 个条目及真实 通过/失败/跳过计数；无任何 agent-reach read/search... 的 argparse invalid choice/usage 刷屏。doctor 至少命中状态报告而 PASS；若渠道探测或 GitHub 更新受环境影响，只能显示 SKIP，不得把该环境状态判为 FAIL。

## 5. 风险与回退

- check-update 仍依赖 GitHub；timeout 15s 和错误关键词把网络故障降为 SKIP，不阻塞其余测试。若 Git Bash 没有 GNU timeout，将该条替换为 agent-reach check-update --help，并在计划外记录环境差异，不能裸跑无限重试。
- Rich 可能在某些终端保留 markup；期望同时匹配标题和状态行，SKIP 同时覆盖 [!]/[X] 的 markup 字面量及中文消息。
- 不执行 setup、install、configure、uninstall、真实 transcribe 或任何平台搜索；这些命令的副作用/凭据要求已由 --help 或前置 install/doctor 阶段覆盖。
