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
- [ ] extraction of single chapter via `ffmpeg` call using chapter information
- [ ] parallelization of per-chapter extraction (user defined parallelism level)
- [ ] command line interface (at least `--infile`, `--outdir`)
- [ ] support for additional CLI options that tweak extraction details: how to name files, etc.
      See the Python and Go versions for examples.

## Usage:

Build main executable:

    $ make build

the program is now in `./zig-out/bin/audiobook_split_ffmpeg_zig`

Run demo:

    $ make demo

Run tests:

    $ make test


## License

Copyright 2025 Markus Holmström (MawKKe)

The works under this repository are licenced under Apache License 2.0.
See file `LICENSE` for more information.
