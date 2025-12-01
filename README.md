# Redis Single-Threading and CPU-Bound Testing

This project demonstrates Redis's single-threaded nature and CPU-bound characteristics using Docker containers and redis-benchmark.

## Quick Start

### Option 1: Automated One-Time Benchmarks
```bash
# Start Redis and run automated benchmarks (runs once and exits)
docker compose up

# Monitor Redis CPU usage in another terminal
docker stats redis-server
```

### Option 2: Continuous Load Testing
```bash
# Start Redis and continuous benchmarking service
docker compose up redis redis-continuous-benchmark -d

# Monitor CPU usage to see sustained ~100% (1 core) usage
docker stats redis-server

# Stop when done
docker compose down
```

### Option 3: Version Comparison Testing
```bash
# Test Redis 6
docker-compose -f docker-compose.redis6.yml up --abort-on-container-exit

# Test Redis 5
docker-compose -f docker-compose.redis5.yml up --abort-on-container-exit

# See detailed comparison results
cat VERSION_COMPARISON.md
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

### 3. Version Performance Comparison
- Compare Redis 5, Redis 6, and Redis 7 under identical conditions
- All versions demonstrate the same single-threaded architecture
- Performance differences are minimal (< 5%) across versions
- See `VERSION_COMPARISON.md` for detailed analysis

## Understanding the Benchmarks

The benchmark container runs several tests:

1. **SET operations** - Write performance
2. **GET operations** - Read performance
3. **Variable client counts** (1, 10, 50, 100 clients) - Shows diminishing returns due to single-threaded bottleneck
4. **LPUSH/LPOP** - List operations (CPU-intensive)
5. **Pipelining tests** - Shows how batching helps reduce round-trip overhead

## Testing Approaches Explained

This project supports two different testing methodologies:

### 1. Docker Compose Services (Automated)

**How it works:**
- Uses the `redis-benchmark` service defined in `docker-compose.yml`
- Runs a predefined set of benchmarks automatically
- Exits after completing all tests

**When to use:**
- Quick verification of Redis behavior
- Automated, repeatable tests
- CI/CD pipeline integration
- One-time performance snapshots

**Command:**
```bash
docker compose up  # Runs once and exits
```

### 2. Manual Docker Run Commands (Custom)

**How it works:**
- Manually launch temporary Redis benchmark containers
- Full control over parameters and concurrency
- Can run multiple benchmarks simultaneously

**When to use:**
- Sustained load testing for CPU monitoring
- Custom test scenarios
- Running many concurrent benchmarks
- Stress testing with specific parameters

**Example:**
```bash
# Start Redis first
docker compose up -d redis

# Run 10 concurrent benchmarks manually
for i in {1..10}; do
  docker run --rm --network redis-test_redis-net redis:7-alpine \
    redis-benchmark -h redis -p 6379 -t set,get,lpush,lpop -n 100000 -c 50 -d 256 -q &
done

# Monitor CPU while benchmarks run
docker stats redis-server
```

**Why this approach for multi-core tests:**

In the multi-core allocation test (MULTI_CORE_TEST.md), we used the manual approach to:
- Run 10 concurrent benchmarks to create sustained load
- Capture 15 CPU samples during active benchmarking
- Demonstrate that even under heavy concurrent load, Redis uses only 1 core

The docker-compose `redis-benchmark` service would run once and exit, making it difficult to capture sustained CPU measurements.

### 3. Continuous Benchmarking Service (Sustained Load)

**How it works:**
- Uses the `redis-continuous-benchmark` service in docker-compose.yml
- Runs benchmarks in an infinite loop
- Provides sustained load for extended CPU monitoring

**When to use:**
- Long-running CPU observation
- Demonstrating consistent single-core usage
- Teaching/demonstration purposes
- Extended performance profiling

**Command:**
```bash
docker compose up redis redis-continuous-benchmark -d
docker stats redis-server  # Watch sustained ~100% CPU
```

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
# Default Redis 7
docker-compose down

# Redis 6
docker-compose -f docker-compose.redis6.yml down

# Redis 5
docker-compose -f docker-compose.redis5.yml down
```

## Documentation

### Testing and Performance
- **README.md** - This file, quick start and overview
- **VERSION_COMPARISON.md** - Detailed Redis 5 vs Redis 6 performance comparison
- **TEST_REPORT.md** - Comprehensive testing report for Redis 5, 6, and 7
- **MULTI_CORE_TEST.md** - Multi-core CPU allocation test results

### Sizing and Architecture Guides
- **POD_SIZING_STRATEGY.md** - ⭐ **Pod memory sizing best practices** (32GB vs 64GB vs 128GB)
- **REDIS_SIZING_GUIDE.md** - General Redis sizing strategies for Kubernetes
- **CLUSTER_SIZING_GUIDE.md** - Redis cluster sizing and architecture for Kubernetes
- **SIZING_FOR_8K_QPS_1MB.md** - Specific sizing example for 8K QPS with 1MB values
- **SIZING_1TB_IMAGE_CACHE.md** - Sizing example for 1TB image cache

### Development
- **CLAUDE.md** - Project guidance for Claude Code
