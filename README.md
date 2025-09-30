# low_and_behold
tiny card game

## Development notes

- This project uses a central animation service `CardAnimator`.
- For runtime consistency, `CardAnimator.gd` should be registered as an Autoload (singleton) in Godot Project Settings.

Add the following to your `project.godot` under the `[autoload]` section if it's not already present:

CardAnimator="*res://scripts/CardAnimator.gd"

## Quick smoke test

There is a tiny smoke test scene/script under `tools/` that attempts to load key scripts. To run it headless (example):

1. Open Godot and run `tools/smoke_test.tscn`, or
2. From the command line (adjust path to your Godot binary):

```bash
/path/to/Godot -s tools/smoke_test.gd
```

The CI workflow included in `.github/workflows/check-autoload.yml` will also verify that `CardAnimator` is present in `project.godot`.
