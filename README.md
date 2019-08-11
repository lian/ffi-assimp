ffi-assimp
==========

Ruby interface to [assimp](https://github.com/assimp/assimp) using Ruby FFI
(Foreign Function Interface).

Usage
-----

```rb
require "ffi-assimp"

Assimp.new("file.stl").open do |scene|
  p scene.info
  p scene.sizes
end
```
