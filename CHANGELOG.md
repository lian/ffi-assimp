## Unreleased

Breaking changes:
- Move from Module to Class.
  Change `Assimp.open_file(path, flags)` to `Assimp.new(path, flags).open`.

- When opening a file, do not yield if `scene` is the scene is `null` to
  prevent null pointer exceptions.

- When opening a file, do not yield `root_node`,
  instead prefer calling `scene.root_node`.

Additions:
- Add `Scene#sizes`.

Fixes:
- Opening with custom `flags` did not forward these flags.

## v0.0.1

First release.
