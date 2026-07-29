# 05 — 实现显式 ChatGPT Ledger Skill

**What to build:** 用户在 Codex 显式执行带准确任务 ID 的 ChatGPT Ledger Skill 后，能看到可追踪的分析阶段并获得一份可核查候选；Skill 绝不自动运行、绝不修改正式账本，也不把原始消息标记为已处理。

**Blocked by:** 03 — 生成安全任务与正式 ChatGPT 账本.

**Status:** completed — runtime activation check NOT RUN (requires unapproved system configuration).

- [x] Skill 仅支持明确任务 ID；任务不存在、已有已接受回执或输入不一致时拒绝处理。
- [x] 执行可见地经历输入盘点、会话分段、主题匹配、内容点比较、覆盖检查和候选发布；已有主题身份原样复用，新主题保持候选。
- [x] 三会话且含重复主题的测试任务产生带来源的内容点和完整输入覆盖，并以原子方式发布候选而不改正式账本。
