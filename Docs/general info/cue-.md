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

The `Check Cue Project` and `Make project Cue` scripts currently validate only that the filename is an `.rpp` file with a non-empty project prefix before the first underscore. They do not validate the Cue ID or version tokens.

## Bus tracks

Inside CUE projects, your instruments should be routed to bus tracks so that you can export multiple instruments of the same group.
Since Reaper does not have any form of "track type", we just prefix the track's name with `B ` (B + Space), followed by an arbitrary, but ideally short track name.

## The EXPO Ruler Lane

A Ruler Lane with the name "EXPO" and timebase "Time" must exist.
Any Region you make here will be available for export. The name of the region is irrelevant, however, EXPO will append the regions name with TC start and TC end numbers. In a single cue project, there must be only one region on the EXPO Ruler Lane. As soon as there are multiple regions on the EXPO lane, the scripts will treat it as a MULTICUE project. More info on the respective page.
Before each export, EXPO will check if the selected region starts and ends on whole frames. If they don't, EXPO will move the start and end points to the nearest whole frame and update the TC displayed in the region name.

## Timebase

On a cue project, you can work in any project timebase you prefer. The `EXPO` ruler lane itself must use the `Time` timebase. The `Check Cue Project` and `Make project Cue` scripts check and can fix this lane setting; they do not change the project's timebase.

The *check* and *make* scripts also validate the project's location in `03_Cues` and the EXPO folder tree. They display the current project framerate for reference but do not compare it with an Assembly project. They do not inspect regions or determine whether the project is a multicue project, that is done during export.

Having the `EXPO` lane on `Time` and the export logic that ensures region starts and ends fall on whole frames avoids timebase-related issues. If you place your export in the Assembly project and everything lines up, your exports will sync up on the dub.