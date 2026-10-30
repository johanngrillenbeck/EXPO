---
title: Make project Cue
layout: default
nav_order: 2
parent: Cue Scripts
---

# Make project Cue

| Info and Status         |          |
| ----------------------- | -------- |
| To be executed from     | Cue      |
| Spec'd                  | ✅        |
| Release version roadmap | v1       |
| Implemented             | ✅        |

Validates the current project against the EXPO Cue project requirements and repairs the missing or incorrectly configured `EXPO` ruler lane.

**Checks:**
1. The project is saved inside the `03_Cues` folder.
2. The EXPO project folder tree exists.
3. The filename is an `.rpp` file with a non-empty project prefix followed by an underscore. Cue ID and version tokens are not checked.
4. An `EXPO` ruler lane exists and uses the `Time` timebase.
5. The current project framerate is displayed for reference.

The script does not change the project timebase, create or change tracks, repair folders or filenames, or inspect regions/multicue status. Remaining path, folder-tree, or filename issues must be fixed manually.