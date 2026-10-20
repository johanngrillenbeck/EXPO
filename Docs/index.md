---
title: Home
layout: home
nav_order: 1
---

# EXPO - Export and Delivery Management Script Collection for Film Scoring

EXPO is a workflow standard with some simple script logic sprinkled on top to make exporting various files for film music projects as effortless as possible.

The scripts are written in lua and can be imported to Reaper via ReaPack.

## Development Philosophy

EXPO is completely *stateless*. That means that the application itself does not store any info about your project that could go out of sync.
Instead, each script gathers the necessary project state from what is actually inside your project directory.

This way, if EXPO says that you have already exported a cue, you can be sure that the WAV files of that cue are indeed in the designated delivery folder. Should you discover anything wrong with those files and delete them, no need to tell EXPO about it. Since re-checking files inside your project directory is not computationally expensive, we'd rather check each time instead of relying on a memory that could be out of date.