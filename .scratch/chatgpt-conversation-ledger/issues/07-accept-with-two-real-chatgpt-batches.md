# 07 — 使用两批真实材料验收 ChatGPT 对话账本

**What to build:** 用户使用两批真实 ChatGPT 归档完成从重新导出、会话选择、显式 Skill、候选确认到账本重启恢复的完整闭环，证明系统会累积有来源的语义记录，同时只处理新增或变化版本且安全去重。

**Blocked by:** none.

**Status:** in progress — real archive is available; waits for the user's first-batch conversation selection and explicit Skill invocation.

- [ ] 全部自动验证通过，第一批三个真实会话（至少两个含同一主题）经确认后证明会话分段、主题合并、内容点去重、来源打开、重点和备注有效。
- [ ] 第二批在已处理会话追加消息并增加新会话后，系统只选择新增或变更版本；确认不会重复创建旧内容点。
- [ ] 重复执行第二批命令不改变正式账本；退出并重启 App 后主题、内容点、处理数量、纠正、重点、备注和回执均保留。

**Automated evidence:** archiver `npm test` passed (106 tests); EvolutionCore `swift test` passed (107 tests); EvolutionHub `swift test` passed (31 tests) and `swift build -c release` passed. Governance unit tests, `scripts/check --source-only`, and full `scripts/check` passed after the explicit `chatgpt-ledger` runtime links were applied. The new archive root `/Users/lessen/Documents/AI-chat/遴选` has 50 index entries, 49 readable structured sidecars, and 417 messages; Hub loaded it with selectable pending conversations. `/Applications/TimeLedger.app` was rebuilt and installed, then restarted to load the current binary.
