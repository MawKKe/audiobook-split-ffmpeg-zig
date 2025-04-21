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


## Setup

Install dependencies:

    $ sudo apt install ffmpeg    # or similar

Build main executable:

    $ zig build

or:

    $ make build

the program is now in `./zig-out/bin/audiobook-split-ffmpeg-zig`.

Run tests:

    $ zig build test

or:

    $ make test


## Usage:

Run help:

    $ ./zig-out/bin/audiobook-split-ffmpeg-zig -h
    Usage:
      audiobook-split-ffmpeg-zig --input-file <path> --output-dir <path>

    Splits audio file into per-chapter files using ffmpeg and chapter metadata

    Options:
      -i, --input-file  Path to input file (required)
      -o, --output-dir  Path to output directory (required)
      -h, --help        Show this help message
      --no-use-title    Don't use chapter title as output filename stem (even
                        if title is available). If title is not available, this
                        option is implied.
      --no-use-title-in-meta
                        Do not set chapter title in output metadata, even if the
                        title information is available.

Note: you can also run the main application using `--` separator with `zig build run`:

    $ zig build run -- -h

Run extraction manually:

    $ ./zig-out/bin/audiobook-split-ffmpeg-zig \
        --input-file src/testdata/beep.m4a \
        --output-dir my-extracted

Now you should have three files in `my-extracted/`:

    $ ls my-extracted/
    0 - It All Started With a Simple BEEP.m4a
    1 - All You Can BEEP Buffee.m4a
    2 - The Final Beep.m4a

You can also run the predefined extraction demo:

    $ make demo


## License

Copyright 2025 Markus Holmström (MawKKe)

The works under this repository are licenced under Apache License 2.0.
See file `LICENSE` for more information.
