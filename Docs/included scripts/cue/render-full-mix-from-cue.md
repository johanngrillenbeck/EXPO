---
title: Render Full Mix from Cue
layout: default
nav_order: 4
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
3. Renders the Master Mix to `05_Delivery`.