---
title: Working with Timecode
layout: default
nav_order: 5
---

# Working with Timecode (TC)

In film and media music, it is essential to work with frame accurate timecode so that your music syncs up to the picture after you have handed off your files.

You therefore should always ask for video files with "burned in timecode" (= always visible on the video itself). That way, you can double check wether Reapers timecode display and the video shows the exact same timecode. If something is off, you know that you probably are on a different framerate than the video file.

EXPO does not make assumptions about the framerate of your projects. It uses what you defined in Reaper's *Project Settings* (`Alt + Enter`).[^1] 

If you are not sure what to select here, ask your production.

## Safety checks
Each EXPO script checks whether your CUE and ASSEMBLY project use the same timecode settings. This is essential to keep them both in sync. It also checks for sample rate, but that's more for convenience.

# References

[^1]: Not to be confused with Reaper's *Preferences* (`Ctrl + P`)