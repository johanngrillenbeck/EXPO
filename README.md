# jg_EXPO - Export and Delivery Management Script Collection for Film Scoring

EXPO is a workflow standard with some simple script logic sprinkled on top to make exporting various files for film music projects as effortless as possible.

The scripts are written in lua and can be imported to Reaper via ReaPack.

## Usage Documentation
This script collection's very detailed documentation can be found under /Docs.
You can read the plain markdown files, but an online version with the beautiful just-the-docs theme will be hosted [here]() in the future.

## Development Documentation

### Jekyll live-reload on windows
When using WSL to open this repo on my windows machine, I need this command to get jekyll live-reload to work reliably:

```terminal
bundle exec jekyll serve --livereload --force_polling
```

Apparently, this is due to how WSL mounts windows paths, but I do not want to clone this repo into WSL and constantly push and pull. We can live with some more microseconds of delay when live-reloading. The world is too fast anyways. I digress.