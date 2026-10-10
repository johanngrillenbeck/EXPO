---
title: Workflow
layout: default
nav_order: 1
---

# Workflow

This collection of scripts allows you to drastically reduce the amount of attention, configuration and mouseclicks needed to
- Export mp3 and mp4 previews of your cues
- Export all STEMs[^2] from your cues in a "pre-mix" state
- Import those STEMs to an assembly project, where you will be doing the final level adjustments and mixing tweaks[^1]
- Export these STEMS again in the "mixed" state
- Export a Full Mix sum that nulls with the mixed STEMs in case the production wants to reduce complexity on the dub mix by just using a single file without instrument layers.

We achieve this by adhering to certain folder structure and filename conventions.
jg_EXPO therefore is more of a standardization of workflow with some simple script logic sprinkled on top.

---

[^1]: I have found that I want and need an additional last mixing pass to get a coherent sound for all cues across a film, just like I would handing it off to a score mixer. This also makes it easier to decide on and control the overall dynamic range of the whole soundtrack by being able to control the relative loudness of cues without switching projects all the time.
[^2]: Please note: We are calling Instrument Group Export Busses "STEMS" here, although "Stereo" as in "STEreo MasterS" could be technically incorrect when working with multichannel files, which is the default for film scoring.