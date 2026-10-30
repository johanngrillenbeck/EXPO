---
title: Check FPS
layout: default
nav_order: 3
parent: Cue Scripts
---

# Check FPS

| Info and Status         |          |
| ----------------------- | -------- |
| To be executed from     | Cue      |
| Spec'd                  | ✅        |
| Release version roadmap | v1       |
| Implemented             | ✅        |

Compares the current Cue project's framerate and drop-frame setting with its paired Assembly project. Both the numeric frame rate and DF/NDF mode must match. A mismatch must be corrected manually; run the check again afterward.

The paired Assembly is derived from the Cue project's prefix and expected at `02_Assembly/<prefix>_Assembly.rpp`. If it is already open and REAPER reports it as clean, EXPO reads its current project state. If it is open with unsaved changes, save it and run the check again. If it is not open, EXPO loads it in a temporary project tab for inspection, closes the temporary tab, and restores the Cue project tab. EXPO does not save either project. REAPER's dirty-state reporting depends on its undo/save-prompt preferences, so ensure those are configured to track unsaved changes when relying on an already-open Assembly tab.

Render and export scripts can call the same silent helper, `H.compareCueAssemblyFrameRate()`, as a preflight and proceed only when its result has `matches == true`.
