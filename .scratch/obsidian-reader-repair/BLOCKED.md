# Blocked

## 2026-07-28 — fresh-build visual and interaction acceptance blocked

The installed `/Applications/TimeLedger.app` has real archived sessions and is the correct user-facing app. The source tree's `swift run --package-path EvolutionHub EvolutionHub` build uses the same product name and bundle identifier as both that installed app and a stale workspace `dist/Evolution Hub.app` process. macOS UI automation therefore attaches to the stale development window instead of the fresh executable, which prevents an honest screenshot or live interaction claim for the new reader.

The four TimeLedger/Obsidian comparison screenshots, real drag-selection, highlight/note persistence after restart, and visual three-round gate are **NOT RUN** for the fresh build. Unit and offline-renderer tests are passing; this is an app-instance isolation issue, not a missing local history fixture or a failed build.

## 2026-07-28 — verification command recovered

The earlier execution-environment authorization error recovered. `cd EvolutionHub && swift test` was rerun after the final small layout/task-list edits: 67 tests, 0 failures, 0 skipped.

## 2026-07-28 — fresh `swift run` did not start

After both test suites passed, the required `cd EvolutionHub && swift run` command itself was submitted for the local source-app visual gate. The command was rejected before process creation by the execution environment's authorization interface (`unknown_parameter: input[10].namespace`). No installed app was opened, overwritten, or used as a substitute. Therefore all Task 3 screenshots and interaction evidence remain **NOT RUN**.

Two later retries of the exact command were initially rejected in the same way before any process was created. The test commands remain independently green.

## 2026-07-28 — source process runs, but cannot be visually attached

Using caches constrained to `/private/tmp` and SwiftPM's `--disable-sandbox` (the outer workspace sandbox remains in force), `swift run --disable-sandbox --package-path EvolutionHub EvolutionHub` reached `Build of product 'EvolutionHub' complete!` and stayed running as the native app. The Computer Use service cannot target raw SwiftPM executables; its `Evolution Hub` target attempts to open the user-confirmed-deleted `/Users/lessen/coding/test/TimeLedger/dist/Evolution Hub.app` and fails `NSCocoaErrorDomain 260`. No installed app was opened as a substitute. Task 3 visual and interaction evidence remain **NOT RUN** until a source-process attachment path is available within the task's `swift run`-only constraint.

Three fresh source launches produced the same result. Process inspection confirms the debug executable is present; Computer Use can only return the Finder window and has no public PID/raw-executable attachment parameter. Recreating the user-deleted old `.app` or opening the installed app would not be valid Task 3 evidence, so neither was done.
