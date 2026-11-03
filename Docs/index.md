---
title: Home
layout: home
nav_order: 1
---

# EXPO - Export and Delivery Management Script Collection for Film Scoring

EXPO is a workflow standard with some simple script logic sprinkled on top to make exporting various files for film music projects as effortless as possible.
The scripts are written in lua and can be imported to Reaper via ReaPack.

## State of the project
EXPO is currently in the earliest of development. I have not even indexed for Reapack yet, as I am still in the process of iterating on and testing my ideas.

Heads-up: EXPO in its current state is very opinionated because it models just my preferred file structure at this very moment in time.
You can either succumb to it - aided by the documentation which I have written with great care - or ... not use it for now.
I have Ideas for how to make EXPO more configurable / modular, e.g. a folder level config-file in which you can specify folder structure on a per project basis.
Some other stuff however (e.g. working with Track-Prefixes) is unlikely to change, because it is just so engrained in how I interact with Reaper (not least because of my other project, MCTM).

## Development Philosophy

EXPO is completely *stateless*. That means that the application itself does not store any info about your project that could go out of sync.
Instead, each script gathers the necessary project state from what is actually inside your project directory.

This way, if EXPO says that you have already exported a cue, you can be sure that the WAV files of that cue are indeed in the designated delivery folder. Should you discover anything wrong with those files and delete them, no need to tell EXPO about it. Since re-checking files inside your project directory is not computationally expensive, we'd rather check each time instead of relying on a memory that could be out of date.