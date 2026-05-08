# Usage

bend reads the MacBook lid angle sensor and prints the angle (in degrees) to
stdout.

## Modes

bend has three modes; they are mutually exclusive.

### Oneshot (default)

Print the current angle once and exit.

```bash
$ bend
96
```

### Watch (`-w`, `--watch`)

Print continuously, one line per reading.

```bash
$ bend --watch
96
96
97
...
```

Exits cleanly on `SIGPIPE` so it can be piped into `head`, `awk`, etc.

### Wait-until (`--wait-until <N[+/-]>`)

Block until the lid angle reaches a threshold, then print the angle and exit.

```bash
bend --wait-until 140    # auto-detect direction from current angle
bend --wait-until 140+   # force wait for >= 140
bend --wait-until 30-    # force wait for <= 30
```

The trailing `+` / `-` forces the direction. Without a suffix, bend infers
direction from the current angle (e.g. current=90, target=140 → wait for above).

## Options

| Flag | Description | Default |
|------|-------------|---------|
| `-i`, `--interval <secs>` | Interval between readings in watch / wait-until modes | `0.5` |
| `-d`, `--delta` | Print change since last reading instead of raw angle (requires `--watch`) | off |
| `--timeout <secs>` | Timeout for `--wait-until` (exits with code 3) | none |
| `-h`, `--help` | Show help | — |
| `-v`, `--version` | Show version | — |

## Exit codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | Sensor not found / unsupported hardware |
| `2` | Invalid usage |
| `3` | Timeout (only with `--wait-until --timeout`) |

## Examples

```bash
# Live feed every 100ms
bend --watch -i 0.1

# How much did the lid move since last reading?
bend --watch --delta

# Sleep until lid closes past 30°, give up after 60s
bend --wait-until 30- --timeout 60
```

## Permissions

bend needs **Input Monitoring** permission. Grant it in:

System Settings → Privacy & Security → Input Monitoring → add your terminal.

Without this, `Sensor.open()` fails and bend exits with code 1.
