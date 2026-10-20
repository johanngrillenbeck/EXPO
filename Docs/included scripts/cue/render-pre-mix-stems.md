---
title: Render pre-mix STEMS
layout: default
nav_order: 3
parent: Cue Scripts
---

# Render pre-mix STEMS

| Info and Status         |     |
| ----------------------- | --- |
| To be executed from     | Cue |
| Spec'd                  | ❌   |
| Release version roadmap | v1  |
| Implemented             | ❌   |

**Script Logic:**
1. For safety: Checks if "Export" Region's Start and End point are on a whole frame number, moves if necessary.
2. Sets "Export" Region Name to "Export $starttc - $endtc" (e.g. "Export 01:02:32:03 - 01:05:01:22")
3. Renders all Bus Track STEMs to folder 03-01_Exports. This uses Reaper's "Do not render files that are likely silent" export functionality, so you will only get files that actually contain audio. No need to manually delete unused busses.

## A note on bus tracks
This script will export every track it thinks is a bus track according to the [track type detection logic](/general%20info/conventions.html).