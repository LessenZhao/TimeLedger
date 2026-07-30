# Obsidian Reader Repair Progress

## Task 0 — 2026-07-29

- Goal: replace the current reader with native selection, a proven offline annotation layer, and durable TimeLedger-owned notes.
- Baseline: `codex/chatgpt-conversation-ledger` at `f3c0d8d`; clean worktree and `git diff --check` clean.
- Baseline tests: EvolutionCore 129/0 failures; EvolutionHub 71/0 failures.
- Order: package/dev-app proof → isolated Recogito spike → anchors/store → shared WKWebView UI → real-app acceptance.
- Maximum risk: third-party anchoring could be incompatible with this Markdown/selection model; on failure keep production unchanged and record evidence.

## Task 1 — 2026-07-29

- `TimeLedger Dev.app` uses `com.lessen.TimeLedger.dev`; temporary artifact and installation completed under `/private/tmp`.
- App contains `Contents/Resources/EvolutionHub_EvolutionHub.bundle`; renaming `reader.js` made `--verify-app` fail, restoring it made the check pass.
- The builder no longer removes or overwrites any app, and runtime missing reader resources now show an error page plus bundle-path log.

## Task 2 — 2026-07-29

- PASS: fixed Recogito 4.2.5 WKWebView fixture restored 7 annotations and rendered 8 highlights after changed font size, line height, and width. It covers Chinese, English, Emoji, links, duplicate text, cross-paragraph selection, table, code, overlap, and loading annotations.
- Repeated local WKWebView run output: `annotations=7`, `orphaned=0`, `initialHighlightCount=8`, `renderedHighlights=8`; screenshot: `/private/tmp/recogito-spike-pass.png`.
- Tarball SHA256: `adf339314d05e79cadf775c3acba260df74875e004257d2e447c9bfbe5692a98`; BSD-3-Clause license and vendored resource record are in `Resources/ObsidianReader/THIRD_PARTY.md`.
- Production reader now uses Recogito; no production `mapTextNodes`, `source.indexOf`, `sourceSelection`, `applyHighlights`, or 150 ms polling remains.

## Task 3 — 2026-07-29

- New notes write only to `records/chatgpt-reading-notes-v2.json` (schema 2); `chatgpt-reading-notes.json` is an explicit legacy path and is not migrated.
- V2 anchors carry source/visible hashes, renderer and selector versions, UTF-16 offset unit, position start/end, exact/prefix/suffix, plus source message or formal asset/version scope.
- Corrupt v2 files throw instead of loading as an empty library. The store writes atomically before replacing in-memory notes; a forced directory-write failure test proves it leaves memory empty and surfaces an error.
- New selection writes now record the actual rendered text SHA-256 and bounded prefix/suffix context. Restore first requires matching source markdown hash, then matching rendered-text hash plus exact position; otherwise it searches the exact quote with context and leaves an ambiguous/missing result unpainted.

## Task 4 — 2026-07-29

- Fresh builds passed `--verify-app`, including `/private/tmp/timeledger-dev-install-20260729-r4/TimeLedger Dev.app`; they contain the expected Recogito JS/CSS/license resources.
- Real archived-session source reader: PASS for navigation and a cross-line native drag selection (`bsidian有什么插件…然后写备注等等`). The Recogito toolbar appeared in the live WKWebView.
- Writing/editing/deleting/restarting a new v2 note, formal-asset reader interaction, and post-restart visual retention are NOT RUN. `写笔记` did not present a composer in the attachable process; r5's resources are verified but the attachable process still reports the old `.build` resource URL, so it is not a valid r5 proof.

## Task 5 — 2026-07-29

- Full automated verification after selector recovery changes: EvolutionCore 129 tests, 0 failures; EvolutionHub 72 tests, 0 failures; `git diff --check` clean.

## Task 0 — 2026-07-28

- Branch and HEAD: `codex/chatgpt-conversation-ledger` at `21e1e35`.
- Initial tests (outside the restricted sandbox cache): `Packages/EvolutionCore && swift test` passed 129 tests, 0 failures; `EvolutionHub && swift test` passed 62 tests, 0 failures.
- `git diff --check` produced no output.
- Judge document is unchanged: 535 lines, 23303 bytes, SHA256 `4ec24732b02a449950ad38d0b2d657561678b2c1e3082704624b228f9e390f77`.
- Obsidian 1.12.7, default theme, reading view, light appearance. Reference window content width is approximately 665 px at the current 1366 px window screenshot; the visible reading column is centered between the left and right panes.
- Reference screenshots:
  - `reference/obsidian-top.jpeg`
  - `reference/obsidian-long-list.jpeg`
  - `reference/obsidian-middle.jpeg`
  - `reference/obsidian-footnotes.jpeg`
- Observation: in this actual file Obsidian renders footnote targets as ordinary body hyperlinks; the end of the rendered document did not show a separate visible footnote list. The implementation still must support standard markdown footnotes as required by the objective.

## Next

## Task 1–3 — implemented, pending visual/interactions acceptance

- Added the single-surface offline Web reader under `EvolutionHub/Sources/EvolutionHub/ChatConversations/ObsidianReader/` and static resources under `EvolutionHub/Sources/EvolutionHub/Resources/ObsidianReader/`.
- Vendored MIT resources: `markdown-it 14.1.0` SHA256 `38c70a1e7ca91ab40e2d9e6e60129851a717ed1c7d4acbbdd41bf9503791cf68`; `markdown-it-footnote 4.0.0` SHA256 `d6fee58a3b56c5742fa18f3e01f1d317cc99975683ebd39c9195cb2aff0c2e42`. Licenses and checksums are in `Resources/ObsidianReader/THIRD_PARTY.md`.
- The session source stage now gives all messages to one `WKWebView`; the catalog uses the message id to request `scrollIntoView`. Every session section carries `conversationId` and `messageId`; a formal-asset section carries `assetId` and `versionId` when available.
- A formal asset uses the same reader with one section. The now-unreachable legacy TextKit `NSTextView` reader was removed from `AnnotatableMarkdownReader`.
- Mapping never falls back to an earlier duplicate text occurrence. A missing forward source match leaves the selection unmapped, and Swift rejects unvalidated source ranges.
- Added source-range guard tests (including the second repeated occurrence) and an offline renderer test. The forced UTF-16 offset-one case failed before quote/source validation, then passed after it was added. A later cross-block regression test (heading/list/quote) also failed `quoteDoesNotMatchSource`, then passed after visible-text validation began stripping only non-visible block syntax. Table and fenced-code cross-block cases are covered too.
- `cd EvolutionHub && swift test`: 70 tests, 0 failures, 0 skipped (baseline was 62), rerun successfully after the final single-scroll-surface, task-prefix, asset-note, and cross-block source-mapping adjustments.
- `/Applications/TimeLedger.app` is the correct installed app and has real archived sessions, including the configured `ChatGPT archive 根目录` under `/Users/lessen/Documents/AI-chat/遴选`. It was opened for live-data inspection only; it does not contain this uninstalled source change.

## Next

`EvolutionHub` and `EvolutionCore` tests have now passed (67 and 129 respectively), and `git diff --check` has no output. The required fresh source command now starts successfully using the constrained temporary Swift caches: `swift run --disable-sandbox --package-path EvolutionHub EvolutionHub` reached `Build of product 'EvolutionHub' complete!` and entered the native app run loop. The current visual blocker is only the automation attachment: it recognizes `.app` bundles but cannot attach to this raw `swift run` executable, and its stale `Evolution Hub` entry points to the user-confirmed-deleted `dist/Evolution Hub.app`. Do not substitute `/Applications/TimeLedger.app`.
