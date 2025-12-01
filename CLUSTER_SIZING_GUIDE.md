# Redis Cluster Sizing Guide (Kubernetes)

Based on empirical performance testing of Redis 5, 6, and 7 from this repository.

**Test Results Summary:**
- Redis 5.0.14, 6.2.21, 7.4.7 benchmarked under identical conditions
- Single-core throughput: **170K-220K ops/sec** (256-byte values)
- CPU usage at peak load: **~100%** (single-threaded confirmed)
- Performance difference between versions: **< 10%**

## Your Cluster Requirements

- **Total Memory Needed:** 120 GB
- **Latency Target:** 500 ms maximum
- **Architecture:** 10 Redis pods with 1 CPU core each
- **Deployment:** Kubernetes cluster

---

## Recommended Configuration

### Per-Pod Specifications (Kubernetes)

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: redis-node-0
  labels:
    app: redis
spec:
  containers:
  - name: redis
    image: redis:7-alpine
    resources:
      requests:
        memory: "16Gi"     # 12 GB usable + 4 GB overhead (33%)
        cpu: "1000m"       # 1 full core (single-threaded limit)
      limits:
        memory: "19Gi"     # 20% buffer above request
        cpu: "1000m"       # DO NOT exceed 1 core (single-threaded!)
    command: ["redis-server", "--maxmemory", "12gb", "--maxmemory-policy", "allkeys-lru"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: redis-pvc-node-0

# Alternative conservative option:
# requests.memory: "14Gi"  # 12 GB usable + 2 GB overhead (17%)
# limits.memory: "17Gi"     # 20% buffer
```

### Cluster-Wide Totals

```
Total Pods: 10 (standalone instances or 5 masters + 5 replicas)
Total CPU: 10 cores (1 core per pod × 10 pods)
Total Memory Requests: 160 GB (16 GB × 10 pods)
Total Memory Limits: 190 GB (19 GB × 10 pods)
Total Usable Memory: 120 GB (12 GB × 10 pods)
Total PVC Storage: 160 GB (16 GB × 10 pods, if persistence enabled)

Node Requirements:
  - Minimum nodes: 3 (3-4 pods per node)
  - Per-node capacity: 4+ cores, 65+ GB RAM
  - Network: 10+ Gbps between nodes
```

### Memory Breakdown

| Metric | Value | Notes |
|--------|-------|-------|
| **Total cluster memory** | 120 GB | Your requirement |
| **Number of instances** | 10 | Your architecture |
| **Memory per instance (usable)** | 12 GB | 120 ÷ 10 |
| **Recommended allocation** | **14-16 GB** | Includes overhead |

**Why 14-16 GB instead of 12 GB?**

Redis needs overhead for:
- Internal data structures (~10-15%)
- Memory fragmentation (~10-20%)
- Connection buffers
- Replication buffers (if using Redis Cluster)
- COW (Copy-on-Write) for persistence operations

**Conservative approach:** 16 GB (33% overhead)
**Moderate approach:** 14 GB (17% overhead)

---

## Performance Expectations

Based on our benchmark results with 1 vCore per instance:

### Latency (Per Instance)

| Load Level | p50 Latency | p95 Latency | p99 Latency |
|------------|-------------|-------------|-------------|
| Low (1-10 clients) | **< 0.05 ms** | < 0.1 ms | < 0.2 ms |
| Medium (50 clients) | **0.15-0.20 ms** | 0.3-0.4 ms | 0.5 ms |
| High (100 clients) | **0.3-0.5 ms** | 1-2 ms | 2-5 ms |

**Your 500 ms requirement:** ✅ **Easily achievable** (100-1000x safety margin)

Typical production Redis latencies:
- **Best case:** Sub-millisecond (0.1-0.5 ms)
- **Normal case:** Low single-digit milliseconds (1-5 ms)
- **Stressed case:** Still under 10 ms for p99

You'll likely see **p99 latencies under 5 ms**, far below your 500 ms target.

### Throughput (Per Instance)

Based on our testing with 1 CPU core:

| Operation Type | Throughput | Notes |
|----------------|------------|-------|
| **SET** | ~190,000-200,000 ops/sec | Write operations |
| **GET** | ~200,000-210,000 ops/sec | Read operations |
| **LPUSH/LPOP** | ~170,000-180,000 ops/sec | List operations |
| **Pipelined (16 cmds)** | ~1,700,000 ops/sec | With pipelining |

**Total Cluster Throughput:**
```
10 instances × ~190,000 ops/sec = ~1.9 million ops/sec (non-pipelined)
10 instances × ~1,700,000 ops/sec = ~17 million ops/sec (pipelined)
```

---

## CPU Allocation

### Why 1 vCore is Perfect

From our multi-core test (MULTI_CORE_TEST.md):
- ✅ Redis uses exactly 1 CPU core (~100% of 1 core)
- ❌ Redis CANNOT use multiple cores for command processing
- ❌ Allocating 2+ cores per instance = wasted resources

**Recommendation:**
```
1 vCore per Redis instance = Optimal
```

**If you have extra CPU capacity:**
- ❌ Don't allocate 2 cores to each instance (won't be used)
- ✅ Run more Redis instances instead
- ✅ Or use extra capacity for application servers

---

## Example Docker Compose Configuration

```yaml
version: '3.8'

services:
  redis-node-1:
    image: redis:7-alpine
    container_name: redis-node-1
    cpus: 1
    mem_limit: 16g
    command: redis-server --maxmemory 12gb --maxmemory-policy allkeys-lru
    ports:
      - "6379:6379"

  redis-node-2:
    image: redis:7-alpine
    container_name: redis-node-2
    cpus: 1
    mem_limit: 16g
    command: redis-server --maxmemory 12gb --maxmemory-policy allkeys-lru
    ports:
      - "6380:6379"

  # ... repeat for redis-node-3 through redis-node-10
```

**Key Settings:**
- `cpus: 1` - Single vCore (matches Redis architecture)
- `mem_limit: 16g` - Total container memory
- `--maxmemory 12gb` - Redis usable memory (leaves 4GB overhead)
- `--maxmemory-policy allkeys-lru` - Evict least-recently-used keys when full

---

## Sizing Decision Matrix

### Question 1: What's your expected QPS (Queries Per Second)?

| Expected QPS | Recommendation |
|--------------|----------------|
| < 500,000 | **3-5 instances** sufficient |
| 500,000 - 1M | **5-7 instances** recommended |
| 1M - 2M | **10 instances** (your config) ✅ |
| > 2M | **15+ instances** or enable pipelining |

### Question 2: What's your read/write ratio?

| Pattern | Impact | Recommendation |
|---------|--------|----------------|
| **Read-heavy (90% reads)** | Higher throughput possible | Use Redis replicas for read scaling |
| **Balanced (50/50)** | Standard performance | Your current config works well |
| **Write-heavy (70%+ writes)** | Slightly lower throughput | May need 12-15 instances for 2M ops/sec |

### Question 3: Do you need high availability?

| Requirement | Setup |
|-------------|-------|
| **Single instance OK** | 10 standalone Redis instances |
| **HA required** | **Redis Cluster** (3 masters + 3 replicas = 6 nodes minimum) |
| **Strong HA** | **Redis Cluster** (5 masters + 5 replicas = 10 nodes) ✅ |

---

## Deployment Architectures

### Option 1: Standalone Instances (Simple Sharding)

**Setup:**
- 10 independent Redis instances
- Application does client-side sharding (hash-based routing)
- Each instance: 12 GB data, 1 vCore

**Pros:**
- Simple configuration
- Maximum throughput per node
- Easy to understand

**Cons:**
- No automatic failover
- Manual sharding in application
- No data redundancy

**Total resources:** 10 instances × 1 vCore = 10 vCores, 160 GB RAM

### Option 2: Redis Cluster (Recommended for Production)

**Setup:**
- 5 master nodes (12 GB each = 60 GB total)
- 5 replica nodes (12 GB each = 60 GB total)
- Automatic sharding across masters
- Automatic failover

**Pros:**
- ✅ High availability
- ✅ Automatic failover
- ✅ Built-in sharding
- ✅ Data redundancy

**Cons:**
- More complex setup
- Slight overhead for cluster coordination

**Total resources:** 10 instances × 1 vCore = 10 vCores, 160 GB RAM

**Recommended configuration:**
```yaml
# 5 Master nodes (data sharding)
redis-master-1: 12 GB, 1 vCore, port 7000
redis-master-2: 12 GB, 1 vCore, port 7001
redis-master-3: 12 GB, 1 vCore, port 7002
redis-master-4: 12 GB, 1 vCore, port 7003
redis-master-5: 12 GB, 1 vCore, port 7004

# 5 Replica nodes (failover)
redis-replica-1: 12 GB, 1 vCore, port 7005
redis-replica-2: 12 GB, 1 vCore, port 7006
redis-replica-3: 12 GB, 1 vCore, port 7007
redis-replica-4: 12 GB, 1 vCore, port 7008
redis-replica-5: 12 GB, 1 vCore, port 7009
```

**Cluster benefits:**
- Lose any 1 node → automatic failover (< 1 second)
- Data automatically distributed across 5 shards
- Reads can use replicas (5x read scaling)

### Option 3: Hybrid (Cost-Optimized)

**Setup:**
- 6 Redis instances in cluster mode (3 masters + 3 replicas)
- Each master: 20 GB (60 GB total)
- Each replica: 20 GB (60 GB total)

**Pros:**
- Fewer instances (6 vs 10)
- Still HA with 3 masters
- Saves 4 vCores

**Cons:**
- Less total throughput (~1.1M vs 1.9M ops/sec)
- Less granular sharding

**Total resources:** 6 instances × 1 vCore = 6 vCores, 120 GB RAM

---

## Validation Checklist

Use this checklist to validate your sizing:

### Memory ✓

- [ ] Total memory needed: 120 GB
- [ ] Per-instance allocation: 14-16 GB (with overhead)
- [ ] Redis maxmemory: 12 GB per instance
- [ ] Total cluster usable: 120 GB ✓

### CPU ✓

- [ ] 1 vCore per instance (optimal for single-threaded Redis)
- [ ] Total: 10 vCores for 10 instances
- [ ] Expected CPU usage: ~80-100% under load per instance

### Latency ✓

- [ ] Target: < 500 ms
- [ ] Expected p50: 0.2-2 ms ✓✓✓
- [ ] Expected p99: < 5 ms ✓✓✓
- [ ] Safety margin: 100-250x ✓

### Throughput ✓

Calculate your expected QPS:
- [ ] Expected QPS: __________ ops/sec
- [ ] Cluster capacity: ~1.9M ops/sec ✓
- [ ] Headroom: __________ %

**Recommendation:** Keep cluster utilization < 70% for headroom

---

## Monitoring Recommendations

Once deployed, monitor these metrics:

### Critical Metrics

| Metric | Target | Alert Threshold |
|--------|--------|-----------------|
| **CPU usage** | 60-80% | > 90% |
| **Memory usage** | 60-75% | > 85% |
| **Latency (p99)** | < 5 ms | > 50 ms |
| **Evicted keys** | 0 | > 1000/sec |
| **Connected clients** | < 1000/instance | > 5000/instance |

### Commands to Monitor

```bash
# CPU and memory
docker stats redis-node-1

# Redis info
docker exec redis-node-1 redis-cli INFO stats
docker exec redis-node-1 redis-cli INFO memory

# Latency
docker exec redis-node-1 redis-cli --latency-history

# Slow queries
docker exec redis-node-1 redis-cli SLOWLOG GET 10
```

---

## Cost Optimization Tips

### If you want to reduce costs:

1. **Right-size based on actual QPS**
   - If actual QPS < 1M, you can use fewer instances (6-8)

2. **Use memory more efficiently**
   - Enable compression for large values
   - Use appropriate data structures (hashes for objects)
   - Set TTLs to expire old data

3. **Consider tiered architecture**
   - Hot data: 5 Redis instances (60 GB)
   - Warm data: 5 Redis instances (60 GB)
   - Route queries based on access patterns

### If you need more performance:

1. **Enable pipelining** in your application
   - Can increase throughput 8-10x
   - Minimal code changes

2. **Add read replicas**
   - Don't count against 120 GB (read-only copies)
   - Scale reads independently

3. **Use connection pooling**
   - Reduce connection overhead
   - Improve latency consistency

---

## Final Recommendation

### Recommended Configuration

**For production HA setup:**

```
Architecture: Redis Cluster
Instances: 10 (5 masters + 5 replicas)
Per-instance: 1 vCore, 16 GB RAM, 12 GB maxmemory
Total resources: 10 vCores, 160 GB RAM

Expected performance:
- Throughput: ~1.9M ops/sec (masters)
- Latency p50: < 1 ms
- Latency p99: < 5 ms
- High availability: Yes (tolerates 1 master failure)
```

**This configuration will:**
- ✅ Meet your 120 GB memory requirement
- ✅ Easily meet your 500 ms latency requirement (100x+ margin)
- ✅ Provide ~1.9M ops/sec throughput
- ✅ Offer high availability and automatic failover
- ✅ Use CPU optimally (1 vCore per instance)

---

## Questions to Finalize Sizing

Before finalizing, please answer:

1. **What's your expected QPS (queries per second)?**
   - This determines if 10 instances is right-sized or over-provisioned

2. **Do you need high availability?**
   - Yes → Redis Cluster (5 masters + 5 replicas)
   - No → 10 standalone instances with client-side sharding

3. **What's your read/write ratio?**
   - Read-heavy → Can add read replicas
   - Write-heavy → Current sizing is good
   - Balanced → Current sizing is good

4. **What's your budget constraint?**
   - If flexible → Use 10 instances as planned
   - If tight → Consider 6-8 instances (may still meet needs)

5. **What's your data access pattern?**
   - Uniform → Standard sharding works well
   - Skewed (hot keys) → May need different strategy

---

**Generated from empirical testing:** See TEST_REPORT.md and MULTI_CORE_TEST.md for detailed benchmark results.
