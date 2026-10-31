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
| Depends on              | Ultraschall API (WAV format string only), ReaImGui, SWS |

**Script Logic:**
- Applies the Cue-project [render safety checks]({% link Docs/general%20info/render-safety-checks.md %}), including Cue/Assembly frame-rate matching and EXPO-region frame alignment.
- For multicue projects, shows a checklist of matched regions; missing cues are reported and skipped.
- Confirms and applies any region naming/frame-alignment changes as one undoable operation.
- Applies render settings through REAPER's native project API and invokes REAPER's built-in render action. The REAPER render-dialog test confirmed that `RENDER_SETTINGS=3` selects “Selected tracks (stems)” in this setup; the action sets and verifies that value before rendering. Each selected cue's Bus Tracks are rendered directly as selected-track stems (not via Master) to `03-01_Exports`. REAPER's "Do not render files that are likely silent" option omits silent bus outputs.
- Uses 48 kHz, Master-channel-count output, custom frame-aligned bounds, and a 24-bit PCM WAV format string. Ultraschall is used only to construct the WAV format string; it does not apply or execute render tables.
- Sets the REAPER render resample config to mode 10 (r8brain free) through SWS `SNM_SetIntConfigVar("projrenderresample", 10)` before each render. This config preference remains set after the script finishes.
- REAPER's native project API does not expose all previous RenderTable options. This action does not explicitly set offline render speed or per-file render-stat sidecars; those options are not guaranteed by this implementation.
- Does not overwrite or silently increment existing files. Any existing pre-mix file matching the same project prefix, cue, and version blocks rendering, including unexpected files from an earlier failed/misconfigured attempt.

## Filename construction

The action combines Cue filename tokens with REAPER render wildcards. It does not pre-validate REAPER's predicted render targets: REAPER may intentionally omit tracks it considers likely silent. EXPO reports the WAV files that REAPER actually creates and checks expected output paths for existing files before rendering.

`[projectPrefix]_[cueId]_[version]_$track_pre-mix_TC-$starttc`

`$track` supplies the Bus Track name and `$starttc` supplies the region start timecode in `HH.MM.SS.FF` format. The script temporarily removes the `B ` bus prefix while rendering so `$track` expands to the stem token, then restores the original track names and selection.

## A note on bus tracks
This script will export every track it thinks is a bus track according to the [track type detection logic]({% link Docs/general%20info/cue-bus_tracks.md %}).
In short: Any track with prefix `B ` (B + Space) is considered a bus track and selected for export.