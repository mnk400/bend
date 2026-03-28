# Bend

Bend let's you read the MacBook lid angle sensor, built in zig.

Bend has the following modes:
- (default): Print the lid angle once and exit
- (watch mode) `-w` or `--watch`: Print the lid angle continuously, a live feed
- (wait mode) `--wait-until`: Block until angle reaches threshold, then exit


**Options**

Bend CLI supports the following options:
- `-i`, `--interval`: Interval for polling angle reads in watch or wait mode (in seconds)
- `--timeout`: Optional timeout in wait mode
- `-h`, `--help`: Shows help
