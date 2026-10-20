---
title: Render preview video
layout: default
nav_order: 7
parent: Included Scripts
---

# Render preview video

| Info and Status         |          |
| ----------------------- | -------- |
| To be executed from     | Assembly |
| Spec'd                  | ❌        |
| Release version roadmap | v1       |
| Implemented             | ❌        |

**Script Logic:**
1. Prompts which Cues and Versions (see Region Names) to render. Preselects the ones with a version that has not been rendered yet.
2. Renders mp4 Preview from the Video Preview Region

If you select more than one cue to be rendered as a video preview, you well get *multiple video files*.
For v2, we might introduce a second tickbox that allows you to select wether you want to render multiple files or one continuous file including all selected cues.