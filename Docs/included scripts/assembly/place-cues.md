---
title: Place cues
layout: default
nav_order: 2
parent: Assembly Scripts
---

# Place cues

| Info and Status         |          |
| ----------------------- | -------- |
| To be executed from     | Assembly |
| Spec'd                  | ❌        |
| Release version roadmap | v1       |
| Implemented             | ❌        |

**Script Logic:**
1. Looks through 03_Cues, 03-01_Exports and 04_Previews to get current state of rendered files as well as CUE project files that don't have corresponding renders.
2. Compares current state of folder structure to current state of ASSEMBLY project
3. Imports new cue version previews or stems onto new lanes at the correct TCstart on the respective tracks, comps the newest versions.[^1] Creates new tracks if necessary.

---

[^1]: Comping is a Reaper native feature for compiling the contents of different lanes into a dedicated comp lane.