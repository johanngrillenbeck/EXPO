---
title: Make project ASSEMBLY
layout: default
nav_order: 1
parent: Included Scripts
---

# Make project ASSEMBLY

| Info and Status         |          |
| ----------------------- | -------- |
| To be executed from     | Assembly |
| Spec'd                  | ❌        |
| Release version roadmap | v1       |
| Implemented             | ❌        |

**Script Logic:**
1. Sets all project settings to the appropriate ASSEMBLY standard
2. Checks for or creates Region / Marker lanes (TBD)
3. Checks for or creates VIDEO track
4. Checks for or creates CUE folder track with at least "Preview" and "Full Mix" child tracks.
5. Checks for correct folder structure
6. Checks for correct file name
7. Outputs project prefix and "everything ok" as final confirmation in the console