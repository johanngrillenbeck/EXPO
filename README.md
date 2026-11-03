# jg_EXPO - Export and Delivery Management Script Collection for Film Scoring

EXPO aims to be a workflow standard with some simple script logic sprinkled on top to make exporting various files for film music projects as effortless as possible.
The scripts are written in lua and can be imported to Reaper via ReaPack.

## State of the project
EXPO is currently in the earliest of development. I have not even indexed for Reapack yet, as I am still in the process of iterating on and testing my ideas.

## Usage Documentation
This script collection's very detailed documentation can be found under /Docs.
You can read the plain markdown files, but an online version with the beautiful just-the-docs theme will be hosted [here]() in the future.

Heads-up: EXPO in its current state is very opinionated because it models just my preferred file structure at this very moment in time.
You can either succumb to it - aided by the documentation which I have written with great care - or ... not use it for now.
I have Ideas for how to make EXPO more configurable / modular, e.g. a folder level config-file in which you can specify folder structure on a per project basis.
Some other stuff however (e.g. working with Track-Prefixes) is unlikely to change, because it is just so engrained in how I interact with Reaper (not least because of my other project, MCTM).

## Development Documentation

### Jekyll live-reload on windows
When using WSL to open this repo on my windows machine, I need this command to get jekyll live-reload to work reliably:

```terminal
bundle exec jekyll serve --livereload --force_polling
```

Apparently, this is due to how WSL mounts windows paths, but I do not want to clone this repo into WSL and constantly push and pull. We can live with some more microseconds of delay when live-reloading. The world is too fast anyways. I digress.