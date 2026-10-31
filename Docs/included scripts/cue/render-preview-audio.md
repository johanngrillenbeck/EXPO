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
| Depends on              | Ultraschall API, ReaImGui |

**Script Logic:**
- For safety: Checks if current project is valid Cue
- For safety: Checks if current Cue Project and Assembly Project have the same FPS setting.
- Iterates through all regions on EXPO Ruler Lane to check if their start and end points are on a whole frame number, moves start forward or end backward if necessary.
- Parses region names on EXPO Ruler Lane:
    - If name matches cue ID **and** version number from the .rpp Cue Project filename, continues
    - Same goes for multiple regions: If their names match the project filename, prompt which ones to export.
    - If none or one region is found but unnamed or named differently, make user confirm rename to `<cuePrefix>_<versionNumber>` or abort export.
    - If one or multiple regions are found that match cue ID but not version number of project filename, make user confirm version number update or abort export.
- Appends timecode (or overwrites existing timecode) of regions that are due to be rendered (e.g. "1m04_v7 01:02:32:03 - 01:05:01:22")
- Looks at the channel configuration of master track. If > 2, ask user if stereo fold down has been applied and give them the option to continue or abort.
- Renders master track as mp3 to 04_Previews with a rendertable according to the render conventions for previews.

**Safety and selection behavior:**
- Aborts if the EXPO lane has no regions, if regions cannot be unambiguously associated with cues in the project filename, or if multiple regions map to the same cue/output.
- In a multicue project, shows matched cues and missing-cue warnings in a ReaImGui checklist. Missing cues are skipped; selected matched cues can still be rendered.
- Treats leading-zero version variants (for example `v01` and `v1`) as the same version. Existing preview files are never overwritten or silently incremented; a conflict aborts and asks the user to check the version index.
- Calculates frame alignment for every EXPO-lane region. After confirming any region-name/version corrections and alignment, applies all approved edits as one undoable operation before rendering.
- If the master has more than two channels, requires confirmation that stereo fold-down has already been applied. Automatic temporary fold-down is deferred to v2.

**v2 roadmap:**
- find a way to automatically apply stereo fold down remporarily during render.

<details markdown="block">
<summary>Under the hood</summary>
- Uses the Ultraschall API to make a render table out of the parameters hardcoded into the script via `ultraschall.CreateNewRenderTable` 
- Then renders the project with this render table via `ultraschall.RenderProject_RenderTable`
</details>