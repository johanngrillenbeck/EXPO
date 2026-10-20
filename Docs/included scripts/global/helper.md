---
title: Helper
layout: default
nav_order: 99
parent: Global Scripts
---

# Helper

**This script provides shared parsing for folder status, project status, filenames, regions, timecode, bus tracks, etc.**

Its functions can be called via the terminal for troubleshooting purposes.

| Info and Status         |          |
| ----------------------- | -------- |
| To be executed from     | Assembly or Cue by another script |
| Spec'd                  | ❌        |
| Release version roadmap | v1       |
| Implemented             | ❌        |

<details markdown="block">
<summary>Under the hood</summary>
- IsValidFolderTree
- IsValidAssembly
- IsValidCue
- CueOrMulticue
- GetBusTracks
- IsValidRegion
- MoveRegionToWholeFrame
</details>