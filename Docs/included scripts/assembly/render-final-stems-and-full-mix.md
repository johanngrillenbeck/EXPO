---
title: Render final STEMS and Full Mix
layout: default
nav_order: 3
parent: Assembly Scripts
---

# Render final STEMS and Full Mix

| Info and Status         |                |
| ----------------------- | -------------- |
| To be executed from     | Assembly       |
| Spec'd                  | ❌              |
| Release version roadmap | v1             |
| Implemented             | ❌              |
| Depends on              | Ultraschall API |

1. Prompts which Cues and Versions to render.
2. Renders each STEM file out to `05_Delivery` (via "Render Item", all Track FX and Item FX are applied!)
3. Renders the Full Mix from the previously rendered STEMS.[^1]
# References

[^1]: EXPO creates temporary new tracks for this inside the Assembly Project, which are deleted after. You don't need the final mixed STEMs in your Assembly Project, because they are exactly what you hear with your mixing applied to the pre-mix STEMs.