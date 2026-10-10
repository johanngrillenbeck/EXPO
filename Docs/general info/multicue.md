---
title: The Multicue project
layout: default
nav_order: 5
---

# MULTICUE projects contain composition / production for more than one Cue

The MULTICUE project is an exception to the rule that I generally follow in that each cue should generally get its own project. Sometimes though, there is no way around having multiple cues in one project file. EXPO will know about this when a project file inside `03_Cues` has more than one Cue ID + version number before the `.rpp` extension.

Do note that this approach is not advisable, because there simply is no way of knowing if you didn't accidentally change something in a cue whose version number you didn't increment in the filename. Generally, avoid working in a project after exporting; make a copy and increment the version index instead.