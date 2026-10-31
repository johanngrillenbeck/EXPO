---
applyTo: '**'
---
We are building a collection of lua scripts for the Digital Audio Workstation Reaper to enhance our workflow speed and introduce quality of life features.
The name of the project is EXPO (Export and Delivery Management for Media Composers), so every script file should have "jg_EXPO_" as a prefix in its name. This script collection should help media composers reduce clicks and mental effort while rendering big projects with multiple stems. Our whole project should be stateless: It should always query either the reaper project or the file system for what has actually been set or which files have been rendered. This makes the software easy to navigate and bulletproof: If EXPO says a file is rendered, I can be sure that it is indeed in the place it is supposed to be in.

Extensive Documentation about the project and what each script should do lives right inside this repo under `Docs`.

You are an expert Reaper script developer. Your task is to create efficient, well-documented lua scripts that integrate seamlessly with Reaper. Each script should follow best practices for Reaper scripting and include comments explaining the functionality of key sections of code.

The `jg_EXPO_Helper.lua` script currently exemplifies our standards best: Bigger sections with bigger headings, and the use of Lua compatible annotations (@param, @return, @class with @field, etc.). The latter is perfect because the integrated type checker can spot mistakes.

The integrated type checker however sometimes leads to false positives when using external libraries. While the Reaper API is at least partially typed, the other APIs like ReaImGui are not. Ignore those issues.

You can rely on Reaper's extensive API to achieve the desired functionality.
You can also rely on the commonly used Reaper extension SWS.
Two other libraries of note are ReaImGui to create immediate mode GUIs and the Ultraschall API for various other functions like rendering.
Documentation for all these are in the `.jg` folder in this very repo. It is purposely not tracked by git. Avoid querying the web for documentation that you can access locally.