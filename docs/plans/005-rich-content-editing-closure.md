# Rich Content Editing Closure Implementation Plan

> **For agentic workers:** Execute inline in the current iOS worktree. Do not dispatch subagents, reset existing changes, commit, or push.

**Goal:** Make every note, thought, and directly linked photo shown in draft/confirmed/timeline cards visible and manageable from an explicit editor, while restoring clear note/thought hierarchy and compact editor layout.

**Architecture:** Keep `TimeEntry`, `ThoughtNote`, and `MediaMoment` unchanged. Close the existing `RichCardContentSession` vertical slice by using one direct-entry-media ownership predicate in display and edit paths, parameterizing shared expandable text by semantic role, and routing every timeline card to an appropriate editor. Preserve originals: removing media detaches the TimeLedger relationship and never deletes Photos assets.

**Tech Stack:** SwiftUI, SwiftData, Swift Testing, XCTest UI tests, existing `RichCardContentView` and media services.

## Global Constraints

- No schema migration or new dependency.
- Preserve all pre-existing dirty worktree changes.
- Tap/expand remains read-only; only the visible pencil enters editing.
- Cancellation has zero persistence.
- Removing an attachment retains `MediaMoment`, App files, and Photos assets.
- Confirmed record project/time remain locked; note/media and linked thoughts remain editable.
- No commit or push in this execution.

---

### Task 1: Align displayed and editable direct media

**Files:**
- Modify: `TimeLedger/Services/TimeEntryAttachmentService.swift`
- Modify: `TimeLedgerTests/TimeEntryAttachmentServiceTests.swift`

**Interface:** `noteAttachments(for:moments:thoughtLinks:) -> [MediaMoment]` returns every media item directly linked to the entry and not linked to a thought, regardless of auto/manual provenance.

- [ ] Change the existing service test so an auto-linked direct photo is expected in the editor list while thought-owned media remains excluded.
- [ ] Run the targeted test and record the expected failure.
- [ ] Remove the provenance filter from `noteAttachments` while keeping entry ownership and thought-media exclusion.
- [ ] Re-run the targeted test and verify green.

### Task 2: Give note and thought text separate semantic presentation

**Files:**
- Modify: `TimeLedger/Views/Thoughts/ThoughtCardView.swift`
- Modify: `TimeLedger/Views/Today/TimeEntryExpandableCard.swift`
- Modify: `TimeLedger/Views/Thoughts/TimeEntryNoteCard.swift`
- Modify: `TimeLedgerUITests/TimeLedgerUITests.swift`

**Interface:** `TimelineExpandableText` accepts a semantic style: note uses smaller secondary text and tighter spacing; thought uses current primary body styling.

- [ ] Add/adjust UI expectations that note and thought remain separately identifiable after expansion.
- [ ] Run the focused UI test to establish red when the environment permits.
- [ ] Add the style input and use note styling in entry/timeline notes and thought styling in thought cards.
- [ ] Add a compact `备注` label to the draft/confirmed card note block; keep the thought lightbulb/time header.
- [ ] Re-run the focused UI test.

### Task 3: Remove nested editor padding and dead space

**Files:**
- Modify: `TimeLedger/Views/RichCardContent.swift`
- Modify: `TimeLedger/Views/Today/TimeEntryEditView.swift`
- Modify: `TimeLedger/Views/RichCardContentDetail.swift`
- Modify: `TimeLedgerUITests/TimeLedgerUITests.swift`

**Interface:** `RichCardContentView` renders compact edit content without adding a second card shell when embedded in a `Form`; editor sheets provide the single outer surface.

- [ ] Add a UI assertion that existing media and Add Media are visible without a large blank editor region.
- [ ] Run the focused UI test to establish red when possible.
- [ ] Remove redundant rich-content card background/padding in edit mode, reduce the text editor minimum height, and remove redundant `已有媒体` copy.
- [ ] Ensure the same compact component works in the standalone thought editor sheet.
- [ ] Re-run the focused UI test.

### Task 4: Add explicit editing for all timeline media variants

**Files:**
- Modify: `TimeLedger/Views/Thoughts/ThoughtStreamView.swift`
- Modify: `TimeLedger/Views/Media/MediaMomentCard.swift`
- Modify: `TimeLedger/Views/Today/TimeEntryEditView.swift`
- Modify: `TimeLedgerUITests/TimeLedgerUITests.swift`

**Interface:** Thought cards edit `ThoughtNote`; note cards edit `TimeEntry`; a linked standalone media card exposes the visible pencil and edits its owning `TimeEntry`. Unlinked standalone media retains its existing management menu and viewer because it has no text container or owning record.

- [ ] Add a UI test that a linked photo-only timeline card exposes an edit button and opens an editor containing that photo.
- [ ] Run the focused UI test to establish red when possible.
- [ ] Add `onEdit` to `MediaMomentCard`, show `VisibleEditButton` when the media has a linked entry, and route it through `ThoughtStreamView` to `TimeEntryEditView`.
- [ ] Keep ellipsis for unlink/delete/retry only.
- [ ] Re-run the focused UI test.

### Task 5: Full verification

**Files:**
- Verify all modified production and test files.

- [ ] Run targeted unit tests for attachment ownership and rich-content persistence.
- [ ] Run task-specific UI tests on `iPhone 17`.
- [ ] Run the complete iOS test suite.
- [ ] Run generic iOS build and filter for `BUILD SUCCEEDED|BUILD FAILED|error:`.
- [ ] Run `git diff --check`, inspect `git diff --stat`, and report remaining unverified real-device behavior honestly.
