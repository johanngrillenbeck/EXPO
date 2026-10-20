---
title: Global Scripts
layout: default
nav_order: 6
---

# Global Scripts

**Global Scripts can be executed from both the Assembly and Cue Project.**

## v2 roadmap
Some scripts might move from Cue or Assembly to Global in future versions of this collection.
For example, it would be great to have just one script for video previews that exports just the one cue preview if you launch it from a cue project but asks you which cues you want previews for if you launch it from an Assembly Project.
My aim is to keep the logic in the respective scripts but make an additional "global" one that decides which of them to launch. This way, existing shortcuts or menus don't break and you can freely opt in to use the new global version instead.

> All script file names are prefaced with `jg_EXPO_`, which is omitted here for better readability.