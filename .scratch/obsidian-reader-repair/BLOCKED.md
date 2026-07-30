# Obsidian Reader Repair Blocked

## 2026-07-29 — desktop final acceptance blocked

- Native live selection works and the Recogito toolbar appears in the source reader. However, pressing `写笔记` through both accessibility and pointer coordinates did not present the Swift note composer.
- The temporary r5 app resource check passes, but the currently attachable process reports its WK resource URL under `EvolutionHub/.build/...`, so it cannot prove the r5 toolbar change is running. Closing only the window left the same bundle-id process available to LaunchServices.
- Do not use `/Applications/TimeLedger.app` as a substitute. Required final live checks remain: prove the toolbar bridge opens the composer, then write/edit/delete/restart a v2 note; formal-asset reader interaction; visual retention after font/width change.

## 2026-07-29 — verification command approval error

- Root cause investigation found `Bundle.module` could fall back to the workspace `.build` bundle after a SwiftPM executable was copied into an app. The reader now prefers `Bundle.main.resourceURL/EvolutionHub_EvolutionHub.bundle` before its SwiftPM fallback.
- Running the local reader regression after that edit is pending: the required SwiftPM sandbox-escalation request was rejected by the approval service with an internal `unknown_parameter: input[4].namespace` error. No alternate test route was used.
