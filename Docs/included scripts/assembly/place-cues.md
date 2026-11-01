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
- Scans the actual files in `03_Cues/03-01_Exports` and `04_Previews`. Imports audio-preview MP3s and pre-mix stem WAVs; video files are not handled by this action. Missing output files are not inferred from Cue project files and are not treated as warnings.
- Skips source files already present in the Assembly project. Existing media and older version lanes are retained.
- Places preview and stem items at the filename's start timecode on fixed lane N for version vN. Creates missing stem tracks under `CUES`, named from the stem token without a `B ` prefix. A version index over 30 prompts before project edits; indexes above 1000 are not supported.
- For each cue, the newest version is determined from the files found. Tracks without an item for that version are intended to be silent for that cue rather than falling back to an older version. This allows you to add preview audio versions without bothering to render stems, and only render them once the cue is approved. Should anything need changing, iterate on your soundtrack by importing just the preview versions to Assembly - and once everyone is happy, render and place the STEMs to do the final mixdown.
- Updates the corresponding `EXPO (Final Audio)` region to the imported cue bounds and names it `<cueID>_<version> <start timecode> - <end timecode>`, matching Cue-project EXPO region naming.
- Creates a missing `EXPO (Video Preview)` region with 10 seconds of padding before and after the cue bounds with name `<cueID>_<version>`. The bounds of existing regions is not changed, only their name updated with the new version.

**Implementation status:** Disk inventory, source de-duplication, lane assignment, imports, and region updates are implemented. 

By the way:
Bus tracks do not need a B prefix inside the Assembly project; they use the instrument shorthand from the filename. By definition, all tracks in Assembly were once Bus tracks from Cues.