# jg_EXPO - Export and Delivery Management Script Collection for Film Scoring

## Documentation

This script collection's very detailed documentation can be found under /Docs.
You can read the plain markdown files, but an online version with the beautiful just-the-docs theme will be hosted [here]() in the future.

Note to self:
When using WSL to open this repo on my windows machine, I need this command to get jekyll live-reload to work reliably:

```terminal
bundle exec jekyll serve --livereload --force_polling
```

Apparently, this is due to how WSL mounts windows paths, but I do not want to clone this repo into WSL and constantly push and pull. We can live with some more microseconds of delay when live-reloading. The world is too fast anyways. I digress.
## Workflow
This collection of scripts allows you to drastically reduce the amount of attention, configuration and mouseclicks needed to
- Export mp3 and mp4 previews of your cues
- Export all STEMs from your cues in a "pre-mix" state
- Import those STEMs to an assembly project, where you will be doing the final level adjustments and mixing tweaks[^1]
- Export these STEMS again in the "mixed" state
- Export a Full Mix sum that nulls with the mixed STEMs in case the production wants to reduce complexity on the dub just using a single file without instrument layers.
### Folder Structure and Filename Conventions:
- 01_Footage
	- RoughCut_v37.mp4
	- PL_v3_nosfx.mp4
	- PictureLock_Final_v2_finalfinal_new_withTC.mp4
- 02_Assembly
	- XY_Assembly.rpp
	- XY_projectSettings.csv
- 03_Cues
	- 03-01_Exports
	- 03-02_SWS-Snapshots
	- XY_1m01_v01.rpp
	- XY_1m01_v02.rpp
	- XY_1m02_v02.rpp
	- XY_1m03_1m04_1m05_v07.rpp
- 04_Previews
- 05_Delivery
#### Project prefix
Decide on a short project prefix, which is an arbitrary string delimited from the next element of the filename with an underscore. `XY` is as legal as `NM-S1-E10`. Note that all project files and exports will carry this prefix to identify the project, so keep it short.
#### Filename Conventions

| File                        | Schema                                                                            | Example                                      | Location      |
| --------------------------- | --------------------------------------------------------------------------------- | -------------------------------------------- | ------------- |
| Assembly project            | `[projectPrefix]_Assembly.rpp`                                                    | TF_Assembly.rpp                              | 02_Assembly   |
| Cue project                 | `[projectPrefix]_[cueId]_[version].rpp`                                           | TF_1m01_v12.rpp                              | 03_Cues       |
| Multicue project            | `[projectPrefix]_[cueId]_[version]_[cueId]_[version]_[cueId]_[version]_[...].rpp` | TF_1m02_v3_1m03_v2_1m06_v4.wav               | 03_Cues       |
| Video preview               | `[projectPrefix]_[cueId]_[version]_preview.mp3`                                   | TF_1m01_v12_preview.mp3                      | 04_Previews   |
| Audio preview               | `[projectPrefix]_[cueId]_[version]_preview.mp4`                                   | TF_1m01_v12_preview.mp4                      | 04_Previews   |
| Pre-mix STEM                | `[projectPrefix]_[cueId]_[version]_[STEM]_pre-mix_TC-[HH.MM.SS.FF].wav`           | TF_1m01_v12_HiStr_pre-mix_TC-01.01.12.19.wav | 03-01_Exports |
| Mixed STEM                  | `[projectPrefix]_[cueId]_[version]_[STEM]_mixed_TC-[HH.MM.SS.FF].wav`             | TF_1m01_v12_HiStr_mixed_TC-01.01.12.19.wav   | 05_Delivery   |
| Full mix created from STEMs | `[projectPrefix]_[cueId]_[version]_full-mix_TC-[HH.MM.SS.FF].wav`                 | TF_1m01_v12_full-mix_TC-01.01.12.19.wav      | 05_Delivery   |

For v1 we limit the scope to:
- Only one cue inside each video preview file.
- No versioning of mixed STEMs from assembly.

The roadmap for v2 includes:
- Being able to select which cues to be included in the video preview
- Introduce versioning of the final mixing process inside the assembly project by introducing version index and having multiple assembly projects, each with one mix version, inside 02_Assembly.
### The Assembly project
This project contains the video files and cue renders. It can be opened as a project tab alongside the cue you are currently working on, so the video can be displayed.

The final mixing process also happens in the assembly project. Here, we can determine the final loudness of all cues next to each other throughout the whole film. We can also do STEM-Mastering by applying processing to the pre-mix STEMS either by Item FX (different processing per cue) or Track FX (the same processing of that STEM across all cues).

Using EXPO allows you to export all pre-mix STEMS and render a full mix that nulls with those STEMS played back together. The production can then decide if they want to use your flattened mix or expand into the STEMS - at unity gain, it will sound the same.

One track has the video file (different versions on lanes).
One folder track CUES has child tracks for:
- Preview
- Full Mix
- `[STEM 1]`[^2] (e.g. "HiWW")
- `[STEM 2]` (e.g. "LoBr")
- `[STEM 3]` (e.g. "Piano")
- ...

STEM tracks are properly named like their counterparts in the CUE projects. EXPO names the files appropriately when exporting pre-mix STEMS from the cues and looks for (and creates) these tracks before placing them onto the assembly timeline.

Lanes are used for versioning, with the most current version of a cue being compiled (comp'ed) into a single comp-lane.[^3] This is because two cues might have a different amount of versions that exist, so simply selecting lanes would not work.
### CUE projects contain actual composition / production
RPP-Projects inside the `03_Cues` folder need to have the project prefix followed by a Cue ID and a version index. The Cue ID is a number (leading zeroes possible), followed by m, followed by another number (leading zeroes possible). "1m01" is as valid as "11m087" or "01m001". The version index is "v" followed by a number (leading zeroes possible).

Again, all elements delimited by `_`.

File Name: `"Project prefix"_"Cue ID"_"version".rpp`
Example: `EX_1m03_v12.rpp`

### MULTICUE projects contain composition / production for more than one Cue
The MULTICUE project is an exception to the rule that I generally follow in that each cue should generally get its own project. Sometimes though, there is no way around having multiple cues in one project file. EXPO will know about this when a project file inside `03_Cues` has more than one Cue ID + version number before the `.rpp` extension.

File Name: `"Project prefix"_"Cue ID"_"version"_"Cue ID"_"version"_"Cue ID"_"version".rpp`
Example: `EX_1m01_v4_1m02_v2_1m03_v2_1m04_v5.rpp`

Do note that this approach is not advisable, because there simply is no way of knowing if you didn't accidentally change a parameter for a cue whose version number you didn't increment in the filename. Generally, avoid working in a project after exporting; make a copy and increment the version index instead.

### What are "Bus"-Tracks again?
Reaper does not supply track types, which is a good thing. But for the scripts to work, and for some human readable navigation in our projects, I have introduced track prefixes in my other script collections MCTM and CURSE, which we will also use here.

A track is a "Bus"-Track if it has the Prefix "B " (B + Space) followed by an arbitrary name.
## v1 render conventions
These are currently hard coded. v2 might introduce a settings panel where you can change these.
### audio previews
**Options**
Sample Rate: 48000 Hz
Channels: Stereo
Full-speed Offline
Mix/process FX at project or hardware sample rate
Resample mode: r8brain free

**Primary output format**
Format: MP3
Mode: Constant bitrate (CBR)
q=2
Bitrate: 320kbps
### video previews
**Options**
Sample Rate: 48000 Hz
Channels: Stereo
Full-speed Offline
Mix/process FX at project or hardware sample rate
Resample mode: r8brain free

**Primary output format**
Format: Windows Media encoder (MPEG-4)
Size: 1280 x 720
Framerate: Get from project!
Video: h.264, 2000 kbps
Audio: AAC, 320 kbps
### Full Mix and STEMS (both pre-mix and mixed)
**Options**
Sample Rate: 48000 Hz
Channels: 6
Full-speed Offline
Mix/process FX at project or hardware sample rate
Resample mode: r8brain free

**Primary output format**
Format: WAV
bit depth: 24 bit PCM

Save outfile.render_stats.html
## Scripts
All script file names are prefaced with `jg_EXPO_`, which is omitted here for better readability.
# References

[^1]: I have found that I want and need an additional last mixing pass to get a coherent sound for all cues across a film, just like I would handing it off to a score mixer. This also makes it easier to decide on and control the overall dynamic range of the whole soundtrack by being able to control the relative loudness of cues without switching projects all the time.
[^2]: Please note: We are calling Instrument Group Export Busses "STEMS" here, although "Stereo" as in "STEreo MasterS" could be technically incorrect when working with multichannel files, which is the default for film scoring.
[^3]: Comping is a Reaper native feature for compiling the contents of different lanes into a dedicated comp lane.
