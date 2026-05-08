# bend

<!-- site:strip-start -->
> Read the MacBook lid angle from the command line. Written in Zig.
<!-- site:strip-end -->

![](assets/demo.gif)

## What is this

MacBooks have a sensor that reports the angle of the lid hinge. macOS doesn't expose it as a number, 
but bend does, via IOKit.

Small native binary. Useful for scripting around lid position, triggering scripts when the lid moves past 
a threshold, or just reading the current angle.

<!-- site:strip-start -->
## Install

```bash
# Homebrew
brew install mnk400/tap/bend

# Or via shell script
curl -fsSL https://raw.githubusercontent.com/mnk400/bend/main/install.sh | bash
```
<!-- site:strip-end -->

## Quick start

```bash
$ bend
96

# Live feed
bend --watch

# Block until the lid closes past 30°
bend --wait-until 30-
```

## Documentation

- [Usage](./docs/usage.md) — modes, options, threshold syntax, exit codes
- [Build from source](./docs/build.md)

## License

MIT — see [LICENSE](./LICENSE).
