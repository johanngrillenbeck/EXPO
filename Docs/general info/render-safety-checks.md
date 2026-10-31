---
title: Workflow
layout: default
nav_order:
---

# Render safety checks

## Renders from Cue Projects
- Checks if current project is valid Cue
- Checks if current Cue Project and Assembly Project have the same FPS setting.
- Iterates through all regions on EXPO Ruler Lane to check if their start and end points are on a whole frame number, moves start forward or end backward if necessary.

**Only for MP3 previews**:
If the master has more than two channels, requires confirmation that stereo fold-down has already been applied. Automatic temporary fold-down is deferred to v2.
The preview action renders the master mix using REAPER's native render action, snapshots/restores native render settings and dirty state, and requires the exact expected MP3 to appear as a new file. Both native render actions use SWS `SNM_SetIntConfigVar("projrenderresample", 10)` to set r8brain free before rendering; this REAPER config preference remains set afterward. Full-speed offline mode is not exposed through the native project render settings used here.

**For pre-mix Bus Track STEMs**:
Pre-mix Bus Track STEMs are rendered directly from the selected tracks (not "via Master") with the channel count of the Master Channel. This is the Cue-project pre-mix exception to the six-channel convention for mixed STEMs and full mixes.

### Cue selection behavior
- Aborts if the EXPO lane has no regions, if regions cannot be unambiguously associated with cues in the project filename, or if multiple regions map to the same cue/output.
- In a multicue project, shows matched cues and missing-cue warnings in a ReaImGui checklist. Missing cues are skipped; selected matched cues can still be rendered.
- Treats leading-zero version variants (for example `v01` and `v1`) as the same version. Existing preview or pre-mix STEM files are never overwritten or silently incremented; a conflict aborts and asks the user to check the version index.