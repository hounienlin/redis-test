# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

This is a Redis testing environment designed to demonstrate and verify Redis's single-threaded architecture and CPU-bound performance characteristics using Docker containers and redis-benchmark.

## Architecture

The setup uses Docker Compose with two services:

1. **redis** - Redis server (version 7-alpine) configured for benchmarking:
   - Persistence disabled (`--save "" --appendonly no`) for pure in-memory performance
   - Limited to 1 CPU core and 512MB memory to clearly demonstrate single-threaded behavior
   - Exposed on port 6379

2. **redis-benchmark** - Automated benchmark runner that executes on startup:
   - Tests various Redis operations (SET, GET, LPUSH, LPOP)
   - Runs tests with different client concurrency levels (1, 10, 50, 100)
   - Compares pipelined vs non-pipelined performance
   - All tests target the redis service over the `redis-net` bridge network

## Common Commands

```bash
# Start Redis and run all benchmarks
docker-compose up

# Start Redis in background without running benchmarks
docker-compose up -d redis

# Monitor CPU usage (watch for ~100% indicating single-core saturation)
./monitor-cpu.sh

# Run continuous load for CPU observation
./continuous-load.sh

# Run custom benchmark
docker run --rm --network redis-test_redis-net redis:7-alpine \
  redis-benchmark -h redis -p 6379 -t set,get -n 100000 -c 50

# Stop all containers
docker-compose down
```

## Key Testing Insights

- **Single-threaded verification**: CPU usage caps at ~100% (1 core) regardless of client count
- **Client scaling**: Throughput increases with concurrent clients but plateaus due to single-threaded bottleneck
- **CPU-bound proof**: All operations are in-memory, so performance is limited by CPU, not I/O
- **Pipelining**: Demonstrates significant throughput gains by batching commands and reducing network round-trips

## Modifying Benchmarks

The benchmark tests are defined in `docker-compose.yml` under the `redis-benchmark` service's `command` section. To add or modify tests:

1. Edit the shell script in the `command` block
2. Use `redis-benchmark` with flags:
   - `-h redis` - target host
   - `-t <operations>` - operations to test (set, get, lpush, lpop, etc.)
   - `-n <requests>` - total number of requests
   - `-c <clients>` - number of parallel connections
   - `-d <bytes>` - data size in bytes
   - `-P <pipeline>` - pipeline N requests
   - `-q` - quiet mode (summary only)
   - `--csv` - CSV output format

## Redis Configuration Notes

The Redis server is intentionally configured without persistence to isolate CPU/memory performance from disk I/O. If testing with persistence is needed, modify the `command` in docker-compose.yml to enable AOF or RDB.
