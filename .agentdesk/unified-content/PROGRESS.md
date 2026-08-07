# Unified Content Progress

## 任务 0（基线）
- HEAD `71759fb`，ahead 1；`@Test` 164；UI `func test` 15；详情串 23
- `xcodebuild test` → **TEST SUCCEEDED**

## 目标
卡片原地读图文/折叠；可见「编辑」一步直达；详情入口 0；触控 ≥44×44 且不重叠。

## 已完成
- 任务 1：新增 `testReadingSurfaceEditIsOneTapAndTouchTargetsAreSafe`，并加强既有 UI 测试
- 任务 2：移除详情入口/路由；统一 VisibleEditButton；TimelineExpandableText 真截断；备注卡无更多；思考/媒体菜单仅低频；今天页展开显示备注/思考/事项；编辑页关联思考为卡片；RichCardContent 去内层描边
- 任务 3 验收：
  - `查看详情|onViewDetail|viewDetail` → **0**
  - `xcodebuild test` → **TEST SUCCEEDED**，fail 0 / skip 0 / total **187**（≥ 任务0）
  - `xcodebuild build generic iOS` → **BUILD SUCCEEDED**
  - `git diff --check` 空；Models/xcodeproj/AGENTS 空差异
  - UI test 方法 16（+1）

## 说明
- 正文点击与展开按钮共用 `toggle()`；UI 对正文点击在模拟器上不稳定，以按钮往返 + 正文控件存在作覆盖
- 现场既有白名单外未提交改动保持不动
