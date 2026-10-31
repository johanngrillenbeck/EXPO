---
title: Render pre-mix STEMS
layout: default
nav_order: 3
parent: Cue Scripts
---

# Render pre-mix STEMS

| Info and Status         |                |
| ----------------------- | -------------- |
| To be executed from     | Cue            |
| Spec'd                  | ✅              |
| Release version roadmap | v1             |
| Implemented             | ✅              |
| Depends on              | Ultraschall API, ReaImGui |

**Script Logic:**
- Applies the Cue-project [render safety checks]({% link Docs/general%20info/render-safety-checks.md %}), including Cue/Assembly frame-rate matching and EXPO-region frame alignment.
- For multicue projects, shows a checklist of matched regions; missing cues are reported and skipped.
- Confirms and applies any region naming/frame-alignment changes as one undoable operation.
- Renders each selected cue's Bus Tracks directly as selected-track stems (not via Master) to `03-01_Exports`. REAPER's "Do not render files that are likely silent" option omits silent bus outputs.
- Uses 48 kHz, Master-channel-count output, full-speed offline rendering, project/hardware FX rate, r8brain free, and 24-bit PCM WAV. Saves per-file render statistics.
- Does not overwrite or silently increment existing files. Existing exports for the same cue/version/stem block rendering.

## Filename construction

The action combines Cue filename tokens with REAPER render wildcards:

`[projectPrefix]_[cueId]_[version]_$track_pre-mix_TC-$starttc`

`$track` supplies the Bus Track name and `$starttc` supplies the region start timecode in `HH.MM.SS.FF` format. The script temporarily removes the `B ` bus prefix while rendering so `$track` expands to the stem token, then restores the original track names and selection.

## A note on bus tracks
This script will export every track it thinks is a bus track according to the [track type detection logic]({% link Docs/general%20info/cue-bus_tracks.md %}).
In short: Any track with prefix `B ` (B + Space) is considered a bus track and selected for export.