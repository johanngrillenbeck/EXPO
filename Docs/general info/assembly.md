---
title: The Assembly project
layout: default
nav_order: 4
---

# The assembly project

This project contains the video files and cue renders. It can be opened as a project tab alongside the cue you are currently working on, so the video can be displayed.

The final mixing process also happens in the assembly project. Here, we can determine the final loudness of all cues next to each other throughout the whole film. We can also do STEM-Mastering by applying processing to the pre-mix STEMS either by Item FX (different processing per cue) or Track FX (the same processing of that STEM across all cues). You can then launch a final export of all STEMS and render a full mix that nulls with those STEMS played back together. The production can then decide if they want to use your flattened mix or expand into the STEMS - at unity gain, it will sound the same.

## Tracks

One track "VIDEO" holds the video file(s)
One folder track "CUES" has child tracks:
- "Preview"
- "Full Mix"
- `[STEM 1]` (e.g. "HiWW")
- `[STEM 2]` (e.g. "LoBr")
- `[STEM 3]` (e.g. "Piano")
- ...

All of those tracks support versioning via lanes. We can leave Reapers default enumeration of lanes as-is. Version 1 is on Lane "1", etc. This goes for video files (where you might get different cuts and have to re-conform), as well as cues (where you might find the magic first try or on v37). The most current version of a cue or video is compiled (comp'ed) into the single comp-lane of the respective track. This is because two cues might have a different amount of versions that exist, so simply selecting lanes would not work. The comp lane is always selected. EXPO takes care to comp the most current cue version of all STEMs, but you can always select a previous version manually.

The STEM tracks are named like their counterparts in the CUE projects. EXPO names the files appropriately when exporting pre-mix STEMs from the cues and looks for (or creates) these tracks before placing the respective items onto them.

## Versioning
You can version your mixes via SWS Snapshots inside one ASSEMBLY project. You can also have multiple ASSEMBLY projects inside your `02_Assembly` folder with a version suffix.

## The EXPO Ruler Lane
Two Ruler Lanes with timebase "Time" must exist:
1. `EXPO (Video Preview)`
2. `EXPO (Final Audio)`

Any Region on those lanes will be available for export.

Regions in the Video Preview Lane should be named with just the `cueID` that it covers. These regions are intended to be manually moved to offer the desired leeway before a cue starts and ends in the video preview. Cues might change in length a bit; if the preview file stays the same, those changes can be more accurately judged by your collaborators, IMHO.

Regions in the Final Audio Lane should not be manually created or renamed. EXPO will create and update them from the media items once you import audio from a Cue Project. It's scheme works like this: `[cueId]_[version]_TCstart-[HH.MM.SS.FF]_TCend-[HH.MM.SS.FF]`. This is handy if you want to integrate other script logic (maybe link a Cue Sheet? - something I've been working on...); You just have to read out the region name to get the projects state, EXPO updates with every file import from Cue to Assembly.

Before each export, EXPO will check if the selected region starts and ends on whole frames. If they don't, EXPO will move the start and end points to the nearest whole frame. For regions on the Final Audio Lane it will update the TC displayed in the region name.