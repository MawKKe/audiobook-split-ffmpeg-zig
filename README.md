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
