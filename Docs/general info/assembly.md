---
title: The Assembly project
layout: default
nav_order: 3
---

# The assembly project

This project contains the video files and cue renders. It can be opened as a project tab alongside the cue you are currently working on, so the video can be displayed.

The final mixing process also happens in the assembly project. Here, we can determine the final loudness of all cues next to each other throughout the whole film. We can also do STEM-Mastering by applying processing to the pre-mix STEMS either by Item FX (different processing per cue) or Track FX (the same processing of that STEM across all cues).

Using EXPO allows you to export all pre-mix STEMS and render a full mix that nulls with those STEMS played back together. The production can then decide if they want to use your flattened mix or expand into the STEMS - at unity gain, it will sound the same.

One track has the video file (different versions on lanes).
One folder track CUES has child tracks for:
- Preview
- Full Mix
- `[STEM 1]`[^2] (e.g. "HiWW")
- `[STEM 2]` (e.g. "LoBr")
- `[STEM 3]` (e.g. "Piano")
- ...

STEM tracks are properly named like their counterparts in the CUE projects. EXPO names the files appropriately when exporting pre-mix STEMS from the cues and looks for (and creates) these tracks before placing them onto the assembly timeline.

Lanes are used for versioning, with the most current version of a cue being compiled (comp'ed) into a single comp-lane.[^3] This is because two cues might have a different amount of versions that exist, so simply selecting lanes would not work.