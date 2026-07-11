# Build from source

## Requirements

- Zig 0.16+
- macOS (the lid sensor is Mac-specific; the binary uses IOKit)

## Build

```bash
zig build                                  # builds to zig-out/bin/bend
zig build run -- --watch --interval 0.3    # build and run with args
```

## Source layout

```
src/
├── main.zig    — CLI argument parsing and mode dispatch
├── sensor.zig  — High-level sensor open/read/close
└── iokit.zig   — Low-level IOKit bindings
```
