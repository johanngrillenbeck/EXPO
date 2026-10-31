---
title: Render preview audio
layout: default
nav_order: 2
parent: Cue Scripts
---

# Render preview audio

| Info and Status         |                |
| ----------------------- | -------------- |
| To be executed from     | Cue            |
| Spec'd                  | ✅            |
| Release version roadmap | v1             |
| Implemented             | ✅              |
| Depends on              | Ultraschall API, ReaImGui, SWS |

**Script Logic:**
- Applies [safety checks]({% link Docs/general%20info/render-safety-checks.md %})
- Parses region names on EXPO Ruler Lane:
    - If name matches cue ID **and** version number from the .rpp Cue Project filename, continues
    - Same goes for multiple regions: If their names match the project filename, prompt which ones to export.
    - If none or one region is found but unnamed or named differently, make user confirm rename to `<cuePrefix>_<versionNumber>` or abort export.
    - If one or multiple regions are found that match cue ID but not version number of project filename, make user confirm version number update or abort export.
- Appends timecode (or overwrites existing timecode) of regions that are due to be rendered (e.g. "1m04_v7 01:02:32:03 - 01:05:01:22")
- Looks at the channel configuration of master track. If > 2, ask user if stereo fold down has been applied and give them the option to continue or abort.
- Renders the master mix as an MP3 to `04_Previews` using REAPER's native render action and project render settings. Ultraschall is used only to create the MP3 format configuration string (320 kbps CBR, quality 2).
- Before rendering, snapshots the current native render settings and project dirty state, then restores them after completion or failure. Each render is counted only if the exact expected MP3 appears as a new file; unexpected or incremented filenames stop the run.

**Native render settings:** Before each native render, the action uses SWS `SNM_SetIntConfigVar("projrenderresample", 10)` to set r8brain free. This is a REAPER config preference and remains set after the script finishes. The action also configures master-mix mode, custom frame-aligned bounds, stereo, 48 kHz, output format/path, and disables tails, normalization, dither, and adding output to the project. Full-speed offline mode is not exposed through the native project render settings used here.

**v2 roadmap:**
- find a way to automatically apply stereo fold down remporarily during render.

<details markdown="block">
<summary>Under the hood</summary>
- Calls REAPER's native “Render project, using most recent render settings” action after setting and reading back the project render settings.
- Uses Ultraschall's `CreateRenderCFG_MP3CBR` helper for the MP3 format string only; rendering is performed by REAPER.
</details>