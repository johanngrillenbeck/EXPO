---
title: Place cues
layout: default
nav_order: 2
parent: Assembly Scripts
---

# Place cues

| Info and Status         |          |
| ----------------------- | -------- |
| To be executed from     | Assembly |
| Spec'd                  | ✅        |
| Release version roadmap | v1       |
| Implemented             | ❌        |

**Script Logic:**
- Scans the actual files in `03_Cues/03-01_Exports`, `04_Previews`, and `05_Delivery`. Imports audio-preview MP3s, pre-mix stem WAVs, and full-mix WAVs; video files and mixed STEM deliverables are not handled by this action. Missing output files are not inferred from Cue project files and are not treated as warnings.
- Reconciles every discovered source file against the Assembly project: existing items are moved to the correct CUES track and reset to the filename's start timecode and named version lane, while missing items are imported. Repeated runs with unchanged files do not add duplicate items. Existing items are listed under `Already placed:` in the completion message.
- Places preview, stem, and full-mix items at the filename's start timecode on the lane named `1`, `2`, `3`, etc. for version v1, v2, v3, etc. Take names are set to the source media filename. Creates missing stem tracks under `CUES`, named from the stem token without a `B ` prefix. A version index over 30 prompts before project edits, because that starts to feel unreasonably high; indexes above 1000 are not supported.
- Assigns every direct child track inside `CUES` to track Group 1, names that group `CUES`, and enables both `Media/Razor Edit Lead` and `Media/Razor Edit Follow`.
- For each cue, selects all placed media items from its latest discovered version across the CUES tracks and runs REAPER's `Add Comp Areas for selected items` action (command 42652) once. After processing the cues, runs `Turn off comping` (command 42692).
- At the end, selects all tracks, opens their fixed item lanes with command 42431, then toggles them closed with command 42430 so the cleanup is deterministic; afterward it restores the user's track and item selections.
- For each cue, the newest version is determined from the files found. Tracks without an item for that version are intended to be silent for that cue rather than falling back to an older version. This allows you to add preview audio versions without bothering to render stems, and only render them once the cue is approved. Should anything need changing, iterate on your soundtrack by importing just the preview versions to Assembly - and once everyone is happy, render and place the STEMs to do the final mixdown.
- Updates the corresponding `EXPO (Final Audio)` region to the imported cue bounds and names it `<cueID>_<version> <start timecode> - <end timecode>`, matching Cue-project EXPO region naming.
- Creates a missing `EXPO (Video Preview)` region with 10 seconds of padding before and after the cue bounds with name `<cueID>_<version>`. The bounds of existing regions is not changed, only their name updated with the new version.

**Implementation status:** Disk inventory, source de-duplication and reconciliation, named shared lanes, imports, latest-version comp areas, and region updates are implemented.

By the way:
Bus tracks do not need a B prefix inside the Assembly project; they use the instrument shorthand from the filename. By definition, all tracks in Assembly were once Bus tracks from Cues.