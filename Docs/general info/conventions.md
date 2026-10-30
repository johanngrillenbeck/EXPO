---
title: Conventions
layout: default
nav_order: 3
---

# Project prefix
Decide on a short project prefix, which is an arbitrary string delimited from the next element of the filename with an underscore. `XY` is as legal as `NM-S1-E10`. Note that all project files and exports will carry this prefix to identify the project, so keep it short. Project prefices **must not** contain underscores.

# Folder Structure

This is the definitive folder structure that your project directory needs to follow. You can add additional folders after `05_Delivery` but mayyybeee choose to not use numbers, as we might add some additional folders to the EXPO spec in case the project grows. EXPO folders will always have number pre-fixes, everything else is ignored.

- 01_Footage
	- RoughCut_v37.mp4
	- PL_v3_nosfx.mp4
	- PictureLock_Final_v2_finalfinal_new_withTC.mp4
- 02_Assembly
	- XY_Assembly.rpp
	- XY_projectSettings.csv
- 03_Cues
	- 03-01_Exports
	- 03-02_SWS-Snapshots
	- XY_1m01_v01.rpp
	- XY_1m01_v02.rpp
	- XY_1m02_v02.rpp
	- XY_1m03_1m04_1m05_v07.rpp
- 04_Previews
- 05_Delivery

# Filename Conventions

| File                        | Schema                                                                            | Example                                      | Location      |
| --------------------------- | --------------------------------------------------------------------------------- | -------------------------------------------- | ------------- |
| Assembly project            | `[projectPrefix]_Assembly.rpp`                                                    | TF_Assembly.rpp                              | 02_Assembly   |
| Cue project                 | `[projectPrefix]_[cueId]_[version].rpp`                                           | TF_1m01_v12.rpp                              | 03_Cues       |
| Multicue project            | `[projectPrefix]_[cueId]_[version]_[cueId]_[version]_[cueId]_[version]_[...].rpp` | TF_1m02_v3_1m03_v2_1m06_v4.rpp               | 03_Cues       |
| Video preview               | `[projectPrefix]_[cueId]_[version]_preview.mp4`                                   | TF_1m01_v12_preview.mp4                      | 04_Previews   |
| Audio preview               | `[projectPrefix]_[cueId]_[version]_preview.mp3`                                   | TF_1m01_v12_preview.mp3                      | 04_Previews   |
| Pre-mix STEM                | `[projectPrefix]_[cueId]_[version]_[STEM]_pre-mix_TC-[HH.MM.SS.FF].wav`           | TF_1m01_v12_HiStr_pre-mix_TC-01.01.12.19.wav | 03-01_Exports |
| Mixed STEM                  | `[projectPrefix]_[cueId]_[version]_[STEM]_mixed_TC-[HH.MM.SS.FF].wav`             | TF_1m01_v12_HiStr_mixed_TC-01.01.12.19.wav   | 05_Delivery   |
| Full mix created from STEMs | `[projectPrefix]_[cueId]_[version]_full-mix_TC-[HH.MM.SS.FF].wav`                 | TF_1m01_v12_full-mix_TC-01.01.12.19.wav      | 05_Delivery   |


As you can see, all file identification tokens are delimited with `_`. Therefore, none of these tokens must contain an underscore.

## Versioning
Wherever EXPO supports versioning, the version index should be `v` + any amount of digits. Its valid to do `v01` or `v7` or `v033201`. Leading zeroes are stripped, then the whole number is compared to determine the order.

# Render Conventions

## v1 render conventions
These are currently hard coded. v2 might introduce a settings panel where you can change these.

### audio previews
**Options**
Sample Rate: 48000 Hz
Channels: Stereo
Full-speed Offline
Mix/process FX at project or hardware sample rate
Resample mode: r8brain free

**Primary output format**
Format: MP3
Mode: Constant bitrate (CBR)
q=2
Bitrate: 320kbps

### video previews
**Options**
Sample Rate: 48000 Hz
Channels: Stereo
Full-speed Offline
Mix/process FX at project or hardware sample rate
Resample mode: r8brain free

**Primary output format**
Format: Windows Media encoder (MPEG-4)
Size: 1280 x 720
Framerate: Get from project!
Video: h.264, 2000 kbps
Audio: AAC, 320 kbps

### Full Mix and STEMS (both pre-mix and mixed)
**Options**
Sample Rate: 48000 Hz
Channels: 6
Full-speed Offline
Mix/process FX at project or hardware sample rate
Resample mode: r8brain free

**Primary output format**
Format: WAV
bit depth: 24 bit PCM

Save outfile.render_stats.html

