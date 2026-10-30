---
title: The Multicue project
layout: default
nav_order: 1
parent: The Cue project
---

# A Multicue project

**A Multicue project contains composition / production for more than one Cue**

The Multicue project is an exception to the rule that I generally follow in that **each cue should generally get its own project**. Sometimes though, there is no way around having multiple cues in one project file. EXPO will know about this when a project file inside `03_Cues` has more than one Cue ID + version number before the `.rpp` extension.

Do note that this approach is not advisable, because there simply is no way of knowing if you didn't accidentally change something in a cue whose version number you didn't increment in the filename. Generally, avoid working in a project after exporting; make a copy and increment the version index instead. With a Multicue project, if you want to make a change to just one cue (and therefore increment the version number of just that one cue in the filename) you need to be especially cautious to not make changes to other cues, if you want to have everything in order. You can change the version number in the filename at any time, though, should you discover that change is needed later on. You just have to do this before rendering anything.

## The EXPO Ruler Lane
A Ruler Lane with the name "EXPO" and timebase "Time" must exist.
Their name must be starting with the cue index and version number corresponding to the filename of your Multicue project. EXPO will then prompt you which cues you want to export every time you launch an export script.