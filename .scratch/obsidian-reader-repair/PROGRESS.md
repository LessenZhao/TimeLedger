# Obsidian Reader Repair Progress

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
