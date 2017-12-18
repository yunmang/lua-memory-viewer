# lua-memory-viewer

## Intro

A snapshot tool for checking memory leak in lua.
The objects in "NewObjectMap" are new between two snapshot, and they are leak objects protentially.
This algo make the report shorter by trimming subtrees of the root new object.

## License

The underlying source code is licensed under the MIT license.
