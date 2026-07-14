# TimeLedger V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` or `superpowers:executing-plans` if executing this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Build TimeLedger V1 as a local-first iOS SwiftUI + SwiftData app for low-friction Lyubishchev-style time recording.

**Architecture:** The app is organized around a continuous `TimeCursor`, SwiftData models, small domain services, and SwiftUI screens. Time is stored as full entries but summarized by natural-day overlap so cross-day records are counted correctly.

**Tech Stack:** SwiftUI, SwiftData, Swift Testing/XCTest UI Tests, Xcode iOS App project.

---

## Current Status

- Xcode project exists at `TimeLedger.xcodeproj`.
- Stage 0 is done.
- Stage 1 code is partially implemented but not verified because iOS 26.5 platform is not installed.
- `xcodebuild -downloadPlatform iOS` was started after disk cleanup but interrupted by the user.
- No residual `xcodebuild` process was found after interruption.

## Global Rules

- Do not add login, cloud sync, subscription, AI summary, complex planning, Apple Watch, widgets, multi-device sync, OCR, social sharing, complex reports, or multi-level category trees in V1.
- Do not hand-write fake Xcode project files.
- Use natural day only: local `00:00:00` to next day `00:00:00`.
- Cross-day records remain one `TimeEntry`, but summary/export must use overlap duration.
- Do not store duration as the primary source of truth; derive from `startAt` and `endAt`.
- Keep `confirmed` records time-locked in normal editing.
- Run verification before declaring any stage complete.
- After every stage report:
  - changed files
  - implemented features
  - how to run/test in Xcode
  - build/test status
  - remaining work

## File Map

### Existing / Created

- `TimeLedger/Models/Project.swift`: SwiftData project model.
- `TimeLedger/Models/TimeCursor.swift`: singleton cursor model.
- `TimeLedger/Models/TimeEntry.swift`: SwiftData time entry model and status enum.
- `TimeLedger/Models/AppSettings.swift`: app settings model.
- `TimeLedger/Services/DateRangeService.swift`: natural-day range and overlap helpers.
- `TimeLedger/Services/TimeCursorService.swift`: cursor bootstrap, quick record, adjustment, skip, undo.
- `TimeLedger/Services/TimeSummaryService.swift`: daily/project/category summary queries.
- `TimeLedger/Utilities/DurationFormatter.swift`: human duration strings.
- `TimeLedger/Utilities/DateFormatterFactory.swift`: date/time display formatters.
- `TimeLedger/Views/Today/TodayView.swift`: main recording screen.
- `TimeLedger/Views/Today/ProjectRowView.swift`: project row and quick-record button.
- `TimeLedgerTests/TimeLedgerTests.swift`: initial service tests.

### To Create

- `TimeLedger/Services/ValidationService.swift`
- `TimeLedger/Services/ExportService.swift`
- `TimeLedger/Views/Today/TimeAdjustmentSheet.swift`
- `TimeLedger/Views/Today/TimeListView.swift`
- `TimeLedger/Views/Today/TimeEntryEditView.swift`
- `TimeLedger/Views/Projects/ProjectManageView.swift`
- `TimeLedger/Views/Projects/ProjectEditView.swift`
- `TimeLedger/Views/Review/ReviewView.swift`
- `TimeLedger/Views/Review/DailyReviewView.swift`
- `TimeLedger/Views/Review/WeeklyReviewView.swift`
- `TimeLedger/Views/Review/MonthlyReviewView.swift`
- `TimeLedger/Views/Settings/SettingsView.swift`
- `TimeLedger/Views/Settings/ExportView.swift`

## Stage 0: Project Bootstrap

**Status:** done.

**Files:**
- `AGENTS.md`
- `CLAUDE.md`
- `PROJECT_STATE.md`
- `CHANGELOG.md`
- `docs/README.md`
- `docs/project-overview.md`
- `docs/plans/initial-build.md`
- `scripts/project-check`

**Verification:**

```bash
scripts/project-check
xcodebuild -list -project TimeLedger.xcodeproj
```

## Stage 1: Base Data and Today Quick Record

**Status:** blocked until iOS platform is installed and current code is compiled.

### Task 1.1: Restore Build Environment

**Files:** no source files expected.

- [ ] Run:

```bash
xcodebuild -downloadPlatform iOS
```

- [ ] Verify project is build-addressable:

```bash
xcodebuild -list -project TimeLedger.xcodeproj
xcodebuild build -scheme TimeLedger -project TimeLedger.xcodeproj -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO
```

Expected: build reaches Swift compilation or succeeds. If it fails, record exact compiler errors before editing.

### Task 1.2: Fix Current Stage 1 Compile Errors

**Files likely involved:**
- `TimeLedger/TimeLedgerApp.swift`
- `TimeLedger/ContentView.swift`
- `TimeLedger/Views/Today/TodayView.swift`
- `TimeLedger/Models/*.swift`
- `TimeLedger/Services/*.swift`
- `TimeLedgerTests/TimeLedgerTests.swift`

- [ ] Run the build command from Task 1.1.
- [ ] Fix SwiftData schema, macro, preview, `@Query`, access-control, or test errors only as required by compiler output.
- [ ] Re-run build after each focused fix.
- [ ] Do not proceed to Stage 2 until build passes.

### Task 1.3: Complete Stage 1 Functional Loop

**Files:**
- Modify `TimeLedger/Views/Today/TodayView.swift`
- Modify `TimeLedger/Views/Today/ProjectRowView.swift`
- Modify `TimeLedger/Services/TimeCursorService.swift`
- Modify `TimeLedger/Services/TimeSummaryService.swift`
- Modify `TimeLedgerTests/TimeLedgerTests.swift`

**Required behavior:**
- First launch creates `TimeCursor`.
- Header shows current unclassified duration.
- User can add common projects.
- Project list shows project name and category.
- Quick record creates a `draft` `TimeEntry`.
- Quick record updates `TimeCursor.cursorAt`.
- Quick record refreshes project subtitle to today's duration.
- Undo deletes last eligible draft and restores cursor.
- Long unclassified threshold shows a blocking prompt for now if `TimeAdjustmentSheet` is not yet implemented.

**Tests to keep/add:**
- `getOrCreateCursor()` creates cursor on first run.
- `quickRecord(project:now:)` creates draft entry and moves cursor.
- `undoLastEntry()` restores cursor.
- confirmed entry cannot be undone.
- non-last entry cannot be undone.
- `todayDuration(for:)` counts draft + confirmed by default.
- cross-day entry is split by natural day.

**Verification:**

```bash
xcodebuild test -scheme TimeLedger -project TimeLedger.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16' -derivedDataPath build/DerivedData
xcodebuild build -scheme TimeLedger -project TimeLedger.xcodeproj -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO
```

If simulator name differs, first run:

```bash
xcrun simctl list devices available
```

## Stage 2: Draft Editing and Time Page

### Task 2.1: Add Time Adjustment Sheet

**Files:**
- Create `TimeLedger/Views/Today/TimeAdjustmentSheet.swift`
- Modify `TimeLedger/Views/Today/TodayView.swift`
- Modify `TimeLedger/Services/TimeCursorService.swift`

**Required behavior:**
- Long press project quick button opens sheet.
- Sheet shows project name, current unclassified duration, note, start time, end time.
- OK creates draft entry and sets cursor to chosen end time.
- "Skip this segment" does not create entry and sets cursor to now.
- Single tap over long-threshold opens the same sheet instead of saving.

### Task 2.2: Add Time List

**Files:**
- Create `TimeLedger/Views/Today/TimeListView.swift`
- Modify `TimeLedger/Views/Today/TodayView.swift`
- Modify `TimeLedger/Services/TimeSummaryService.swift`
- Modify `TimeLedger/Utilities/DateFormatterFactory.swift`

**Required behavior:**
- Segmented control switches between "待办" and "时间".
- Time page shows today entries with overlap against today.
- Draft entries are gray; confirmed entries are black.
- Row shows project name, time range, note summary, status, disclosure.
- Bottom status bar shows current unclassified duration, current time, and remaining time today.

### Task 2.3: Add Time Entry Editor

**Files:**
- Create `TimeLedger/Views/Today/TimeEntryEditView.swift`
- Modify `TimeLedger/Views/Today/TimeListView.swift`
- Modify `TimeLedger/Services/TimeCursorService.swift`

**Required behavior:**
- Draft: project, note, startAt, endAt editable; delete allowed; single confirm entry can be added later in Stage 3 if not ready.
- Confirmed: project and note editable; time read-only; delete hidden.
- Editing the most recent draft updates `TimeCursor.cursorAt` if original `endAt == cursorAt`.

**Verification:** build, test, and manual Xcode simulator flow.

## Stage 3: Confirmed State Machine

### Task 3.1: Add Validation Service

**Files:**
- Create `TimeLedger/Services/ValidationService.swift`
- Modify `TimeLedgerTests/TimeLedgerTests.swift`

**Required behavior:**
- `endAt > startAt`
- duration > 0
- project exists
- no overlap with other entries
- gaps are allowed

**Tests:**
- `endAt <= startAt` invalid.
- overlapping entries invalid.
- gap entries valid.
- invalid draft cannot be confirmed.

### Task 3.2: Confirm All Drafts For Today

**Files:**
- Modify `TimeLedger/Views/Today/TimeListView.swift`
- Modify `TimeLedger/Views/Today/TimeEntryEditView.swift`
- Modify `TimeLedger/Services/ValidationService.swift`

**Required behavior:**
- "确认转换" checks all current natural-day draft records.
- If valid, all today's drafts become confirmed.
- If overlap exists, show error and do not partially confirm.

### Task 3.3: Cancel Confirmation

**Files:**
- Modify `TimeLedger/Views/Today/TimeEntryEditView.swift`

**Required behavior:**
- Confirmed edit view shows weak "取消确认" button.
- Button opens confirmation alert with required text.
- Confirming changes status back to draft.
- Does not alter `TimeCursor.cursorAt`.

## Stage 4: Natural-Day Summary and Overlap Validation

### Task 4.1: Complete Date Range Service

**Files:**
- Modify `TimeLedger/Services/DateRangeService.swift`
- Modify `TimeLedgerTests/TimeLedgerTests.swift`

**Required behavior:**
- `startOfNaturalDay(for:)`
- `endOfNaturalDay(for:)`
- `naturalDayRange(for:)`
- `weekRange(for:)`
- `monthRange(for:)`
- `overlapDuration(...)`
- `hasOverlap(...)`

### Task 4.2: Complete Summary Service

**Files:**
- Modify `TimeLedger/Services/TimeSummaryService.swift`
- Modify `TimeLedgerTests/TimeLedgerTests.swift`

**Required behavior:**
- `todayDuration(for:)`
- `todayDurationByProject()`
- `durationForProject(projectId, from, to)`
- `entriesForDate(date)`
- `confirmedEntriesForDate(date)`
- `draftEntriesForDate(date)`
- `totalDurationForDate(date)`
- `categorySummaryForDate(date)`
- `projectSummaryForDate(date)`

**Tests:**
- single project today's total.
- multiple entries today's total.
- cross-day split.
- include/exclude draft.

## Stage 5: Review and Export

### Task 5.1: Review Pages

**Files:**
- Create `TimeLedger/Views/Review/ReviewView.swift`
- Create `TimeLedger/Views/Review/DailyReviewView.swift`
- Create `TimeLedger/Views/Review/WeeklyReviewView.swift`
- Create `TimeLedger/Views/Review/MonthlyReviewView.swift`
- Modify `TimeLedger/ContentView.swift`

**Required behavior:**
- Review entry point is reachable from app navigation.
- Daily review shows total time, category summary, project summary, and timeline.
- Weekly and monthly views can be simple aggregate lists in V1.
- Default uses confirmed entries, with option to include draft.

### Task 5.2: Export Service and UI

**Files:**
- Create `TimeLedger/Services/ExportService.swift`
- Create `TimeLedger/Views/Settings/SettingsView.swift`
- Create `TimeLedger/Views/Settings/ExportView.swift`
- Modify `TimeLedger/ContentView.swift`

**Required behavior:**
- CSV export fields: date, startAt, endAt, durationMinutes, projectName, categoryName, note, status.
- JSON backup includes projects, timeEntries, settings.
- Markdown daily report follows the requested structure.
- Export obeys `exportOnlyConfirmed`.
- Cross-day records are rendered by current day's overlap in Markdown report.

## Stage 6: Polish and Full Verification

### Task 6.1: Project Management

**Files:**
- Create `TimeLedger/Views/Projects/ProjectManageView.swift`
- Create `TimeLedger/Views/Projects/ProjectEditView.swift`
- Modify `TimeLedger/Views/Settings/SettingsView.swift`

**Required behavior:**
- Add, edit, archive, delete project.
- Edit name, category, emoji, color, sort order.
- No category tree.

### Task 6.2: Error States and Empty States

**Files:**
- Modify relevant `Views/` files.

**Required behavior:**
- Empty project list prompt.
- Empty time list prompt.
- Validation errors are user-readable.
- Long unclassified warning uses `TimeAdjustmentSheet`.

### Task 6.3: Final Tests and Manual Acceptance

**Files:**
- Modify `TimeLedgerTests/TimeLedgerTests.swift`
- Modify `TimeLedgerUITests/TimeLedgerUITests.swift`

**Required verification:**

```bash
scripts/project-check
xcodebuild build -scheme TimeLedger -project TimeLedger.xcodeproj -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO
xcodebuild test -scheme TimeLedger -project TimeLedger.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16' -derivedDataPath build/DerivedData
```

Manual acceptance in Xcode:
- Launch app.
- Add project.
- Quick record.
- Verify cursor resets.
- Verify project subtitle changes to today's total.
- Undo last record.
- Long press opens adjustment sheet.
- Create draft with adjusted time.
- Confirm all drafts.
- Cancel confirmation.
- Verify overlap is blocked and gap is allowed.
- Export CSV, JSON, Markdown.

## Stage Report Template

Use this exact report after each stage:

```md
## 阶段 N：<名称>

### 改了哪些文件
- `<file>`：<purpose>

### 实现了哪些功能
- <feature>

### 如何在 Xcode 中运行和测试
- Open `TimeLedger.xcodeproj`
- Select `TimeLedger` scheme
- Select available iOS Simulator or device
- Run build/test commands:
  - `<command>`

### 是否通过构建
- Build: passed/failed/blocked
- Test: passed/failed/blocked
- Evidence: <exact command and key output>

### 还有哪些待办
- <remaining item>
```

## Immediate Next Step

Resume from Stage 1:

```bash
xcodebuild -downloadPlatform iOS
```

Then:

```bash
xcodebuild build -scheme TimeLedger -project TimeLedger.xcodeproj -destination 'generic/platform=iOS' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO
```

If the build fails, inspect compiler errors before editing. Do not begin Stage 2 until Stage 1 build and tests are either passing or explicitly blocked with evidence.
