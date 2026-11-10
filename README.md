# glassjar python

The CPython that [glassjar](https://github.com/glassjar-dev/engine) runs in the browser:
CPython 3.15 for `wasm32-wasip1`, built with CPython's own WASI build (`Platforms/WASI`)
and WASI SDK 33, plus the C libraries that the standard library's optional modules need.

| Module | Library |
| --- | --- |
| `zlib`, `gzip`, `zipfile` (deflate) | zlib 1.4 |
| `bz2` | bzip2 1.0.8 |
| `lzma` | xz 5.8.4 (liblzma) |
| `sqlite3` | SQLite 3.54.1 (no threads, mmap, WAL or extensions) |
| `decimal` (C) | CPython's bundled libmpdec |

Not available, as on any WASI Python: `ssl`, `hashlib`'s OpenSSL hashes (the built-in
ones work), `ctypes`, `readline`, `multiprocessing`, `curses`, `tkinter`.

## Output

`dist/python.wasm`: the interpreter without DWARF (10.3 MB, 3.0 MB gzip).

`dist/python-stdlib.tar.gz`: `usr/local/lib/python315.zip` (579 precompiled modules,
hash-based `.pyc`, stored uncompressed so imports never inflate) and the `os.py` /
`lib-dynload` landmarks `getpath` uses to find the prefix. The prefix is `/usr/local`, like
the 3.11 runtime it replaces, so the debugger can tell the student's files from library code.
Both files are reproducible from the pinned inputs in `versions.env`.

## Build

Needs Python 3.11+, `wasmtime`, `pkg-config` and `rsync`.

```sh
./build.sh      # WASI SDK, deps (build-deps.sh), CPython, then package.sh
```

CI (`.github/workflows/build.yml`) runs the same build on Linux.
