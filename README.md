# Redis Single-Threading and CPU-Bound Testing

This project demonstrates Redis's single-threaded nature and CPU-bound characteristics using Docker containers and redis-benchmark.

## Quick Start

```bash
# Start Redis and run benchmarks
docker-compose up

# Monitor Redis CPU usage in another terminal
docker stats redis-server
```

## What This Tests

### 1. Single-Threaded Nature
- Redis uses a single thread for command processing
- Increasing concurrent clients doesn't proportionally increase throughput
- CPU usage on the Redis container should peak at ~100% (1 core)

### 2. CPU-Bound Behavior
- Redis performance is limited by CPU speed, not I/O
- Operations are in-memory, so disk I/O is not a bottleneck
- The benchmark tests various operations to show CPU utilization

## Understanding the Benchmarks

The benchmark container runs several tests:

1. **SET operations** - Write performance
2. **GET operations** - Read performance
3. **Variable client counts** (1, 10, 50, 100 clients) - Shows diminishing returns due to single-threaded bottleneck
4. **LPUSH/LPOP** - List operations (CPU-intensive)
5. **Pipelining tests** - Shows how batching helps reduce round-trip overhead

## Monitoring CPU Usage

### Real-time monitoring:
```bash
docker stats redis-server
```

Look for:
- CPU % should approach 100% during heavy load (1 full core)
- It won't exceed 100% even with many concurrent clients

### Detailed CPU monitoring:
```bash
# Watch CPU usage continuously
watch -n 1 'docker stats redis-server --no-stream'
```

## Running Custom Benchmarks

```bash
# Run a specific test manually
docker run --rm --network redis-test_redis-net redis:7-alpine \
  redis-benchmark -h redis -p 6379 -t set,get -n 100000 -c 50 -d 256

# Test with different data sizes
docker run --rm --network redis-test_redis-net redis:7-alpine \
  redis-benchmark -h redis -p 6379 -t set -n 50000 -c 50 -d 1024

# Test specific commands
docker run --rm --network redis-test_redis-net redis:7-alpine \
  redis-benchmark -h redis -p 6379 -t lpush,lpop,sadd,hset -n 100000
```

## Expected Observations

1. **Single Core Usage**: Redis will use approximately 100% of a single CPU core, not more
2. **Client Scaling**: Adding more clients improves throughput up to a point, then plateaus
3. **Pipelining Benefits**: Pipelining significantly improves throughput by reducing round-trip latency
4. **Memory Operations**: All operations are fast because Redis is in-memory (no disk I/O bottleneck)

## Cleanup

```bash
docker-compose down
```
