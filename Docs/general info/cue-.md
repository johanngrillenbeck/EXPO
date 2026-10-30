---
title: The Cue project
layout: default
nav_order: 4
---

# The CUE project

**The cue project contains your actual composition and production.**

RPP-Projects inside the `03_Cues` folder need to have the project prefix followed by a Cue ID and a version index. The Cue ID is a number (leading zeroes possible), followed by m, followed by another number (leading zeroes possible). "1m01" is as valid as "11m087" or "01m001". The version index is "v" followed by a number (leading zeroes possible).

File Name: `"Project prefix"_"Cue ID"_"version".rpp`
Example: `EX_1m03_v12.rpp`

## The EXPO Ruler Lane

A Ruler Lane with the name "EXPO" and timebase "Time" must exist.
Any Region you make here will be available for export. The name of the region is irrelevant, however, EXPO will append the regions name with TC start and TC end numbers. In a single cue project, there must be only one region on the EXPO Ruler Lane. As soon as there are multiple regions on the EXPO lane, the scripts will treat it as a MULTICUE project. More info on the respective page.
Before each export, EXPO will check if the selected region starts and ends on whole frames. If they don't, EXPO will move the start and end points to the nearest whole frame and update the TC displayed in the region name.