# Timeline Editing Progress

## Task 0 — Baseline (2026-08-06)

### git status --short
```
 M TimeLedger/Services/TimelineProjection.swift
 M TimeLedger/Services/UITestFixtureService.swift
 M TimeLedger/Views/Media/MediaMomentCard.swift
 M TimeLedger/Views/Thoughts/ThoughtCardView.swift
 M TimeLedger/Views/Thoughts/ThoughtEditView.swift
 M TimeLedger/Views/Thoughts/ThoughtStreamView.swift
 M TimeLedgerTests/TimelineProjectionTests.swift
 M TimeLedgerUITests/TimeLedgerUITests.swift
?? .agentdesk/timeline-semantics/
?? TimeLedger/Views/Thoughts/TimeEntryNoteCard.swift
```

### HEAD
`71759fb feat(ios): improve review insights and export flow`

### Existing uncommitted ownership (do not overwrite)
- `TimelineProjection.swift` + tests: timeline semantics work (prior thread)
- `UITestFixtureService.swift` / `TimeLedgerUITests.swift`: media fixture + filter/unlink coverage
- `MediaMomentCard.swift` / `ThoughtCardView.swift` / `ThoughtStreamView.swift` / `TimeEntryNoteCard.swift`: prior timeline card work
- `ThoughtEditView.swift`: unlink confirm alert only; **still has freeze root cause** `@Query private var mediaLinks: [ThoughtMediaLink]`

### Freeze repro path (current fixture)
1. Launch with `-ui-testing -ui-media-fixture`
2. 今天 → 草稿 → 展开「Fixture 草稿项目」→ 编辑
3. 记录详情 → 点击已有思考「Fixture 草稿思考全文…」
4. Expected freeze: AttributeGraph invalidation loop from `ThoughtEditView` unfiltered `@Query [ThoughtMediaLink]`
5. Confirmed root cause per brief: remove query → navigation works immediately

## Task 1 — Regression coverage (completed)

- Added UI coverage for opening an existing thought without hanging, full-page long-note editing, and immediate note/thought editing from Timeline.
- Added deterministic accessibility identifiers for note, linked/unlinked thought, and media-card menus.
- RED evidence before the card/menu fix:
  - `testTimelineFilterSheetShowsCorrectKinds`: failed at the new media-menu assertion (`TimeLedgerUITests.swift:269`).
  - `testTimelineEditsNoteAndThoughtCardsImmediately`: failed at the new note-menu assertion (`TimeLedgerUITests.swift:511`).
- The earlier full-suite failure at line 366 came from selecting the first generic thought menu even when it belonged to an unlinked thought. The test now targets `timeline.thought.menu.linked`.

## Task 2 — Freeze and editor fix (completed)

- Removed the unfiltered `@Query [ThoughtMediaLink]` from `ThoughtEditView`.
- Added the one-shot, fetch-limited `ThoughtMediaLinkService.hasAttachedMedia(for:)` path.
- Thought and note editors now use full-height `TextEditor` surfaces.
- Record-detail note editing writes back to the local draft; Timeline note editing uses the narrow `TimeCursorService.updateNote` path.
- Service tests cover media presence/absence and draft/confirmed note-only invariants.

## Task 3 — Flomo-style card unification (completed)

- Note, thought, and standalone media records now share white 18pt continuous-radius cards, subdued time, type pill, and top-right ellipsis menu.
- Standalone media actions moved from inline controls into `timeline.media.menu`.
- Replaced fixed media-grid heights with width-derived aspect ratios to avoid overflow/overlap.
- Real-pixel inspection found the video duration accidentally rendered as source text; corrected it to `· <1分钟` and added a UI regression assertion.
- Final screenshot: `/Users/lessen/.codex/visualizations/2026/08/06/019fd61a-b0ac-7f31-a1ad-2fa6a410d0da/timeledger-timeline-fixed.png`.

## Verification — final (2026-08-06)

- Targeted menu/card UI tests: `TEST SUCCEEDED`.
- Targeted formatted-duration UI test: `TEST SUCCEEDED`.
- Full `TimeLedgerUITests`: 18/18 passed, `TEST SUCCEEDED`.
- Full `TimeLedgerTests`: 152/152 passed, `TEST SUCCEEDED`.
- Generic iOS build with `CODE_SIGNING_ALLOWED=NO`: `BUILD SUCCEEDED`.
- Simulator note: after manual visual inspection, XCTest runner was temporarily denied by SpringBoard. Closing the manual Simulator window and returning the device to a clean shutdown restored the same test command; no business-code workaround was added.
- HEAD remains `71759fb`; no commit and no push.
