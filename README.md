# audiobook-split-ffmpeg-zig

Split audiobook file into per-chapter files using chapter metadata and ffmpeg.

Useful in situations where your preferred audio player does not support chapter metadata.

---

**NOTE**: this is a work in progress; it serves mostly as my personal exercise project
for learning Zig.

Try one of these feature-complete versions if you need to split an audiobook into chapters:
- https://github.com/MawKKe/audiobook-split-ffmpeg (Python version)
- https://github.com/MawKKe/audiobook-split-ffmpeg-go (Go version)

---

TODO implement:
- [x] read chapters from file into internal structured representation (`readChapters`)
- [x] extraction of single chapter via `ffmpeg` call using chapter information
- [x] command line interface (at least `--infile`, `--outdir`)
- [ ] parallelization of per-chapter extraction (user defined parallelism level)
- [ ] support for additional CLI options that tweak extraction details: how to name files, etc.
      See the Python and Go versions for examples.

## Usage:

Build main executable:

    $ zig build  # or 'make build'

the program is now in `./zig-out/bin/audiobook_split_ffmpeg_zig`.

Run help:

    $ ./zig-out/bin/audiobook_split_ffmpeg_zig -h
    Usage:
      audiobook_split_ffmpeg_zig --input-file <path> --output-dir <path>

    Options:
      -i, --input-file  Path to input file (required)
      -o, --output-dir  Path to output directory (required)
      -h, --help        Show this help message

Note: you can also run the main application using `--` separator with `zig build run`:

    $ zig build run -- -h

Run tests:

    $ zig build test  # or 'make test'

Run demo extraction:

    $ make demo

## License

Copyright 2025 Markus Holmström (MawKKe)

The works under this repository are licenced under Apache License 2.0.
See file `LICENSE` for more information.
