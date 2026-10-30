---
title: Check Cue Project
layout: default
nav_order: 1
parent: Cue Scripts
---

# Check Cue Project

| Info and Status         |          |
| ----------------------- | -------- |
| To be executed from     | Cue      |
| Spec'd                  | ✅        |
| Release version roadmap | v1       |
| Implemented             | ✅        |

Validates the current project against the EXPO Cue project requirements and reports any issues. If the `EXPO` ruler lane is missing or does not use the `Time` timebase, the script offers to repair it.

**Checks:**
1. The project is saved inside the `03_Cues` folder.
2. The EXPO project folder tree exists.
3. The filename is an `.rpp` file with a non-empty project prefix followed by an underscore. Cue ID and version tokens are not checked.
4. An `EXPO` ruler lane exists and uses the `Time` timebase.
5. The current project framerate is displayed for reference.

The script does not restrict or change the project timebase, modify tracks, repair folders or filenames, or inspect regions/multicue status. Path, folder-tree, and filename issues must be fixed manually.
