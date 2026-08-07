# Content Unification Progress

- [x] 任务 0：2026-08-07 复核 `codex/ios/rich-media-timeline`、HEAD `c22bc8996042edf2fafc125613de312dbd617a34`、工作树干净（相对远端 ahead 2）。
- [x] 基线测试源码计数：TimeLedgerTests `@Test` 164；TimeLedgerUITests `test*` 26；按任务书要求未跑全量。
- [x] 任务 1 实现：V1/V2、启动备份门禁、逐行检查点回填、auto/unlinked 纯媒体随记、8 个迁移测试；红证据为缺失实现编译失败，当前 `build-for-testing` 编译成功，Simulator 实跑受环境阻塞。
- [x] 任务 2 实现：唯一 `ContentEditorSession`、owner 隔离原子草稿、revision 冲突拒绝、附件增量、`SaveContent` 单事务、pending/partial/failed/ready 恢复状态；新增“旧媒体草稿不得覆盖新正文”回归，编译转绿，实跑受环境阻塞。
- [x] 任务 3 实现：活动 View/Projection、UI fixture、文件导出、SyncEnvelope/Mirror 1.0、手机网络快照均读写新模型；V1 往返只含既有 entityType；旧内容服务在 App 活动路径调用数 0，UI 26 个既有统一编辑回归已同步新入口/文案。
- [x] 静态反向检查：单元测试源码 183、UI 26；无 skip/todo；EvolutionCore/Hub/xcodeproj/AGENTS/CI diff 为空；可见界面无“思考/备注/草稿”旧术语。
- [x] 单元验收：iPhone 17 Simulator 实跑 184 passed / 0 failed / 0 skipped；迁移、旧 revision、旧草稿覆盖、V1 往返均实际通过。
- [ ] UI 验收：唯一一次全量为 203 passed / 7 failed / 0 skipped（总计 210）；随后 6 个旧入口失败定向转绿，`testTimelineFilterSheetShowsCorrectKinds` 达三轮上限，最小修正后未再复跑，详见 BLOCKED。
- [x] 构建与静态验收：generic iOS `BUILD SUCCEEDED`；`git diff --check` 通过；EvolutionCore/Hub/协议工程/AGENTS/CI diff 为空；单元/UI 源码计数 184/26。
- [ ] 真机硬门槛：已发现指定 iPhone 16 Plus，但状态 `unavailable`，未安装、未执行真机场景，详见 BLOCKED。
- 最大风险：SwiftData 旧未版本化库兼容、备份/迁移中断恢复、旧 View/Projection 隐式读写、CoreDevice 当前不可用。
- 让步顺序：数据与媒体不丢 > 单一事实源 > 可恢复迁移 > 编辑一致 > 界面精致 > 速度。
