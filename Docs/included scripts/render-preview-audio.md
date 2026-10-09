---
title: Render preview audio
layout: default
nav_order: 4
parent: Included Scripts
---

# Render preview audio

| Info and Status         |     |
| ----------------------- | --- |
| To be executed from     | Cue |
| Spec'd                  | ❌   |
| Release version roadmap | v1  |
| Implemented             | ❌   |

**Script Logic:**
1. For safety: Checks if "Export" Region's Start and End point are on a whole frame number, moves if necessary.
2. Sets "Export" Region Name to "Export $starttc - $endtc" (e.g. "Export 01:02:32:03 - 01:05:01:22")
3. Looks at the channel configuration of master track and adds appropriate fold down chain
4. Renders master track as mp3 to 04_Previews