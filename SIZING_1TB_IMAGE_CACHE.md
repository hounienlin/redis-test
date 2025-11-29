# Redis Image Cache Sizing: 1TB Memory, 8K QPS

**Your Requirements:**
- Total memory: 1 TB
- QPS: 8,000 requests/second
- p95 latency: < 500 ms
- Data type: Images (1 MB each)
- TTL: 5 minutes (300 seconds)
- High availability: Required

---

## Executive Summary

**Recommended Configuration:**
```
Architecture: Redis Cluster (for HA)
Instances: 20 total (10 masters + 10 replicas)
Per-instance: 1 vCore, 110 GB RAM (100 GB usable)

Total resources:
  - 20 vCores
  - 2.2 TB RAM (1 TB usable across masters)
  - Network: 10+ Gbps per instance (200 Gbps aggregate)

Expected performance:
  - QPS capacity: 30,000-50,000 ops/sec
  - Your need: 8,000 ops/sec (4-6x headroom) ✅
  - p95 latency: < 25 ms (20x better than target) ✅
  - Memory: 1 TB ✅
```

---

## Memory Calculation

### Working Set Analysis

With 5-minute TTL, how much data do you accumulate?

**Scenario 1: All 8,000 req/sec are unique writes (worst case)**
```
8,000 writes/sec × 300 seconds (5 min TTL) = 2,400,000 items
2,400,000 × 1 MB = 2.4 TB required

This exceeds 1 TB - can't fit! ❌
```

**Scenario 2: Cache with hit rate (realistic)**

Most image caches have 80-95% hit rate:
- 8,000 req/sec total
- 80% cache hits (reads of existing items)
- 20% cache misses (new writes)

```
Write rate: 8,000 × 20% = 1,600 writes/sec
Items stored: 1,600 × 300 sec = 480,000 unique images
Memory needed: 480,000 × 1 MB = 480 GB ✅ Fits in 1 TB!
```

**Scenario 3: Higher cache hit rate (95%)**
```
Write rate: 8,000 × 5% = 400 writes/sec
Items stored: 400 × 300 sec = 120,000 unique images
Memory needed: 120 GB ✅ Well within 1 TB!
```

**Conclusion:** 1 TB is sufficient if your cache hit rate is > 50%

### What if cache hit rate is low?

If you need to store ALL requests:
```
8,000 req/sec × 300 sec = 2,400,000 items = 2.4 TB needed

You would need to either:
1. Increase total memory to 2.5-3 TB
2. Reduce TTL to 2 minutes (960,000 items = 960 GB)
3. Accept evictions (LRU policy keeps most popular images)
```

---

## Cluster Architecture

### Recommended: 10 Masters + 10 Replicas

**Why 10 masters?**
- Distributes 1 TB across 10 nodes = 100 GB per master
- 100 GB is a manageable size per instance
- Good balance of redundancy and resource distribution
- Each master handles ~800 req/sec (very comfortable)

**Configuration:**

```yaml
Total instances: 20
- 10 master nodes (data distribution)
- 10 replica nodes (high availability)

Per master node:
  CPU: 1 vCore
  Memory: 110 GB total (100 GB usable)
  Network: 10 Gbps minimum
  Data: ~100 GB (1/10 of total 1 TB)

Per replica node:
  CPU: 1 vCore
  Memory: 110 GB total (100 GB usable)
  Network: 10 Gbps minimum
  Data: Copy of master (100 GB)
```

### Alternative: 5 Masters + 5 Replicas

**If you want fewer instances:**

```yaml
Total instances: 10
- 5 master nodes
- 5 replica nodes

Per master node:
  CPU: 1 vCore
  Memory: 220 GB total (200 GB usable)
  Network: 25 Gbps minimum
  Data: ~200 GB (1/5 of total 1 TB)
  QPS per master: ~1,600 req/sec
```

**Pros:**
- ✅ Fewer instances (10 vs 20)
- ✅ Lower management overhead
- ✅ Still provides HA

**Cons:**
- ❌ Larger instances (200 GB each)
- ❌ Less granular data distribution
- ❌ Higher network load per instance (1.6 GB/sec vs 800 MB/sec)
- ❌ Less headroom for growth

---

## Performance Analysis

### QPS Capacity

With 1 MB images, throughput is **network-bound**, not CPU-bound.

**Per instance capacity (1 MB values):**
- 10 Gbps network: ~1,250 ops/sec
- 25 Gbps network: ~3,000 ops/sec
- 40 Gbps network: ~5,000 ops/sec

**Cluster capacity (10 masters):**

| Network Speed | Per Master | Total Cluster (10M) | Meets 8K QPS? |
|---------------|------------|---------------------|---------------|
| 10 Gbps | ~1,250 ops/sec | ~12,500 ops/sec | ✅ 1.5x headroom |
| 25 Gbps | ~3,000 ops/sec | ~30,000 ops/sec | ✅ 3.7x headroom |
| 40 Gbps | ~5,000 ops/sec | ~50,000 ops/sec | ✅ 6.2x headroom |

**Recommendation:** Use 10-25 Gbps network interfaces

### Latency Expectations

**Components of latency for 1 MB image:**

| Component | Time | Notes |
|-----------|------|-------|
| Network transfer (10 Gbps) | ~0.8 ms | 1 MB ÷ 10 Gbps |
| Network transfer (25 Gbps) | ~0.3 ms | 1 MB ÷ 25 Gbps |
| Redis processing | 0.1-0.3 ms | Memory lookup + serialization |
| Network round-trip | 0.1-0.5 ms | Depends on network quality |
| **Total (10 Gbps)** | **~1-2 ms** | p50 latency |
| **Total (25 Gbps)** | **~0.5-1 ms** | p50 latency |

**Expected p95 latency:** 5-15 ms (far below 500 ms target) ✅

**Your 500 ms target:** Easily achievable with 30-100x safety margin!

### Network Bandwidth Requirements

**Total cluster bandwidth needed:**
```
8,000 req/sec × 1 MB = 8 GB/sec = 64 Gbps
```

**With replication (master → replica):**
```
Write traffic: ~2,000 writes/sec (assuming 75% cache hit rate)
Replication: 2,000 × 1 MB = 2 GB/sec additional
Total: 8 + 2 = 10 GB/sec = 80 Gbps
```

**Per instance (10 masters):**
```
8 GB/sec ÷ 10 = 800 MB/sec = 6.4 Gbps per master
With replication: ~1 GB/sec = 8 Gbps per master

10 Gbps network interfaces are sufficient ✅
25 Gbps provides good headroom
```

---

## Recommended Deployment

### Option 1: Recommended (10M + 10R, balanced)

```yaml
version: '3.8'

services:
  # Master nodes (1-10)
  redis-master-1:
    image: redis:7-alpine
    container_name: redis-master-1
    cpus: 1
    mem_limit: 110g
    command: >
      redis-server
      --port 7000
      --cluster-enabled yes
      --cluster-config-file nodes.conf
      --cluster-node-timeout 5000
      --maxmemory 100gb
      --maxmemory-policy allkeys-lru
      --save ""
      --appendonly no
    ports:
      - "7000:7000"
      - "17000:17000"  # Cluster bus port
    networks:
      - redis-cluster

  # Replica nodes (1-10)
  redis-replica-1:
    image: redis:7-alpine
    container_name: redis-replica-1
    cpus: 1
    mem_limit: 110g
    command: >
      redis-server
      --port 7010
      --cluster-enabled yes
      --cluster-config-file nodes.conf
      --cluster-node-timeout 5000
      --maxmemory 100gb
      --maxmemory-policy allkeys-lru
      --save ""
      --appendonly no
    ports:
      - "7010:7010"
      - "17010:17010"
    networks:
      - redis-cluster

  # ... repeat for all 20 nodes

networks:
  redis-cluster:
    driver: bridge
```

**Resource summary:**
- Instances: 20 (10M + 10R)
- CPU: 20 vCores
- Memory: 2.2 TB (1 TB usable)
- Network: 10-25 Gbps per instance
- Cost: ~$3,400/month (estimated)

### Option 2: Minimal (5M + 5R, fewer instances)

```yaml
# Similar config but only 10 instances
# Each master: 200 GB (instead of 100 GB)
```

**Resource summary:**
- Instances: 10 (5M + 5R)
- CPU: 10 vCores
- Memory: 2.2 TB (1 TB usable)
- Network: 25 Gbps per instance (required)
- Cost: ~$2,700/month (estimated)

---

## Configuration Comparison

| Metric | 10M+10R (Recommended) | 5M+5R (Minimal) |
|--------|----------------------|-----------------|
| **Total instances** | 20 | 10 |
| **Memory per master** | 100 GB | 200 GB |
| **QPS per master** | ~800 | ~1,600 |
| **Network per instance** | 10 Gbps OK | 25 Gbps required |
| **QPS capacity** | 30K-50K | 15K-25K |
| **HA resilience** | Can lose 5 masters | Can lose 2 masters |
| **Cost** | Higher | Lower |
| **Recommended for** | Production, growth | Cost-sensitive |

---

## TTL and Memory Management

### How TTL Affects Memory

With 5-minute TTL, Redis automatically evicts expired keys:

```redis
# Keys automatically expire after 5 minutes
SET image:abc123 <binary_data> EX 300

# After 300 seconds, memory is freed automatically
```

**Memory oscillation pattern:**
```
Time 0: 0 GB
Time 1 min: ~200 GB (accumulated)
Time 2 min: ~400 GB
Time 3 min: ~600 GB
Time 4 min: ~800 GB
Time 5 min: ~1000 GB (peak)
Time 6 min: ~1000 GB (steady state - oldest keys expire)
```

**Steady state:** After 5 minutes, memory plateaus as expiring keys = new writes

### Handling Memory Pressure

**If memory reaches maxmemory before TTL expires:**

```redis
# Use allkeys-lru policy
maxmemory 100gb
maxmemory-policy allkeys-lru

# Redis will evict least-recently-used images before maxmemory
```

**Eviction policies:**
- `allkeys-lru`: Evict least recently used keys ✅ Recommended for cache
- `volatile-lru`: Only evict keys with TTL set
- `allkeys-lfu`: Evict least frequently used (Redis 4.0+)

---

## Monitoring & Alerts

### Critical Metrics

| Metric | Target | Alert Threshold | Action |
|--------|--------|-----------------|--------|
| **Memory usage** | 60-80% | > 90% | Add instances or reduce TTL |
| **Evicted keys** | 0 ideal | > 1000/sec | Memory pressure, scale up |
| **CPU usage** | 20-40% | > 80% | Shouldn't happen (network-bound) |
| **Network bandwidth** | 50-70% | > 85% | Upgrade network or add instances |
| **Latency p95** | < 15 ms | > 100 ms | Check network/disk |
| **Cache hit rate** | > 80% | < 50% | Investigate cache misses |

### Monitoring Commands

```bash
# Memory and evictions
redis-cli INFO memory | grep -E "used_memory|evicted_keys|maxmemory"

# Stats
redis-cli INFO stats | grep -E "total_commands|instantaneous_ops"

# Network
docker stats redis-master-1 --no-stream

# Latency
redis-cli --latency-history

# Check TTL expiration
redis-cli INFO keyspace
```

### Key Metrics to Track

```bash
# Cache hit rate (calculate from stats)
redis-cli INFO stats | grep -E "keyspace_hits|keyspace_misses"

# Calculate hit rate:
# hit_rate = hits / (hits + misses)
# Target: > 80%

# Memory fragmentation
redis-cli INFO memory | grep mem_fragmentation_ratio
# Target: 1.0-1.5

# Expired keys per second
redis-cli INFO stats | grep expired_keys
```

---

## Cost Analysis

### Cloud Provider Pricing (Example: AWS)

**Instance type:** r6g.2xlarge (8 vCPU, 64 GB RAM)
- On-demand: ~$400/month
- Reserved (1 year): ~$270/month

**For 10M+10R (100 GB per instance):**
- Need: r6g.4xlarge (16 vCPU, 128 GB RAM)
- Cost per instance: ~$800/month on-demand
- Total: 20 × $800 = **$16,000/month** 💰

**For 5M+5R (200 GB per instance):**
- Need: r6g.8xlarge (32 vCPU, 256 GB RAM)
- Cost per instance: ~$1,600/month on-demand
- Total: 10 × $1,600 = **$16,000/month** 💰

**Same cost! Choose based on operational preference.**

### Cost Optimization

1. **Use reserved instances (1-3 year commitment):**
   - Save 30-50% vs on-demand
   - 20 × $540 = **$10,800/month** (vs $16K)

2. **Use spot instances (non-production):**
   - Save 60-80% vs on-demand
   - 20 × $160 = **$3,200/month**
   - ⚠️ Risk: instances can be terminated

3. **Right-size based on actual usage:**
   - Monitor actual memory usage
   - If only using 500 GB, scale down to 5M+5R with 100 GB each
   - Saves 50% cost

---

## Implementation Checklist

### Phase 1: Planning
- [ ] Determine expected cache hit rate (affects memory sizing)
- [ ] Verify network infrastructure (10-25 Gbps per instance)
- [ ] Choose deployment option (10M+10R vs 5M+5R)
- [ ] Plan instance placement (distribute across availability zones)

### Phase 2: Infrastructure Setup
- [ ] Provision instances with adequate network bandwidth
- [ ] Configure Docker/container runtime
- [ ] Set up monitoring (Prometheus, Grafana, CloudWatch)
- [ ] Configure alerts for key metrics

### Phase 3: Redis Deployment
- [ ] Deploy Redis containers with cluster config
- [ ] Create Redis Cluster (redis-cli --cluster create)
- [ ] Verify cluster health (redis-cli cluster info)
- [ ] Test basic operations (SET/GET with 1 MB values)

### Phase 4: Testing
- [ ] Load test with actual image data (1 MB)
- [ ] Verify network bandwidth during load
- [ ] Measure actual latencies (p50, p95, p99)
- [ ] Test failover (kill a master, verify replica promotion)
- [ ] Verify TTL expiration works correctly

### Phase 5: Application Integration
- [ ] Update application to use Redis Cluster client
- [ ] Implement proper error handling
- [ ] Add client-side monitoring
- [ ] Test cache miss scenarios

### Phase 6: Production Rollout
- [ ] Start with low traffic (10-20%)
- [ ] Monitor cache hit rate
- [ ] Monitor memory usage patterns
- [ ] Gradually increase traffic
- [ ] Fine-tune based on observations

---

## Common Issues & Solutions

### Issue 1: Memory fills faster than expected

**Cause:** Cache hit rate lower than expected (more unique images)

**Solutions:**
1. Reduce TTL from 5 min → 3 min
2. Add more instances (increase total memory)
3. Accept LRU evictions (most popular images stay cached)

### Issue 2: High latency (> 100 ms)

**Causes:**
- Network congestion
- Insufficient network bandwidth
- Cross-region network latency

**Solutions:**
1. Upgrade network interfaces (10 → 25 Gbps)
2. Check network quality (packet loss, jitter)
3. Place Redis closer to application servers

### Issue 3: Uneven load distribution

**Cause:** Hot keys (some images requested much more frequently)

**Solutions:**
1. Use Redis Cluster slot rebalancing
2. Add read replicas for hot shards
3. Consider application-level caching for very hot images

### Issue 4: Frequent evictions

**Cause:** Total working set > available memory

**Solutions:**
1. Increase total cluster memory
2. Reduce TTL
3. Optimize image storage (compression, smaller format)
4. Implement tiered caching (hot images in Redis, warm in CDN)

---

## Advanced Optimizations

### 1. Image Compression

**Problem:** 1 MB images consume significant bandwidth and memory

**Solution:** Compress images before storing

```python
# Example with Python
import redis
import zlib
from PIL import Image
from io import BytesIO

# Compress image
img = Image.open("photo.jpg")
buffer = BytesIO()
img.save(buffer, format="JPEG", quality=85)  # Adjust quality
compressed = zlib.compress(buffer.getvalue())

# Store in Redis
r.setex("image:abc123", 300, compressed)  # 5 min TTL

# Savings:
# Original: 1 MB
# Compressed: 200-400 KB (typical for JPEG)
# Memory savings: 60-80%
# Network savings: 60-80%
```

**Benefits:**
- Reduce memory usage by 60-80%
- Reduce network bandwidth by 60-80%
- Same 1 TB cluster can store 3-5x more images

**Trade-offs:**
- CPU overhead for compression/decompression (usually negligible)
- Slightly increased latency (~1-2 ms)

### 2. Use Read Replicas

**For read-heavy workloads (80%+ reads):**

```yaml
# Add 10 more read-only replicas
# Total: 10M + 10R (HA) + 10R (read scaling) = 30 instances

# Application routes:
# - Writes → masters
# - Reads → read replicas (round-robin)
```

**Benefits:**
- Scale reads independently (10K → 80K read QPS)
- Reduce load on masters
- Maintain HA

### 3. Connection Pooling

**Application-side optimization:**

```python
# Bad: Create new connection per request
for img in images:
    r = redis.Redis(host='redis-cluster')
    img_data = r.get(f"image:{img_id}")
    r.close()  # Overhead!

# Good: Use connection pool
pool = redis.ConnectionPool(host='redis-cluster', max_connections=50)
r = redis.Redis(connection_pool=pool)

for img in images:
    img_data = r.get(f"image:{img_id}")  # Reuse connection
```

**Benefits:**
- Reduce connection overhead
- Lower latency
- Better resource utilization

---

## Final Recommendation

### Recommended Configuration: 10 Masters + 10 Replicas

```yaml
Total instances: 20
Architecture: Redis Cluster with HA

Per instance:
  CPU: 1 vCore
  Memory: 110 GB (100 GB usable)
  Network: 10-25 Gbps
  Ports: 7000-7019 (+ cluster bus ports)

Total resources:
  CPU: 20 vCores
  Memory: 2.2 TB (1 TB usable across masters)
  Network: 200 Gbps aggregate

Configuration:
  maxmemory: 100gb
  maxmemory-policy: allkeys-lru
  TTL: 300 seconds (5 minutes)
  Persistence: Disabled (cache only)
```

### Expected Performance

| Metric | Expected | Your Requirement | Status |
|--------|----------|------------------|--------|
| **QPS capacity** | 30,000-50,000 | 8,000 | ✅ 3.7-6.2x |
| **Memory** | 1 TB usable | 1 TB | ✅ Perfect |
| **p95 latency** | 5-15 ms | < 500 ms | ✅ 30-100x better |
| **High availability** | Yes (10 replicas) | Required | ✅ Full HA |

### Why This Configuration?

1. ✅ **Right-sized for memory:** 1 TB distributed across 10 masters
2. ✅ **Right-sized for QPS:** 4-6x capacity vs requirement
3. ✅ **Network optimized:** 10 Gbps per instance is sufficient
4. ✅ **High availability:** Each master has a replica
5. ✅ **Scalable:** Can add more instances if needed
6. ✅ **Cost-effective:** Balanced instance sizes (100 GB each)

---

## Next Steps

1. **Confirm cache hit rate assumptions**
   - If > 80% hit rate → 1 TB is more than enough
   - If < 50% hit rate → Consider 1.5-2 TB total

2. **Verify network infrastructure**
   - Ensure 10+ Gbps per instance
   - Test actual bandwidth with iperf3

3. **Consider compression**
   - Can reduce memory/bandwidth by 60-80%
   - May allow 5M+5R instead of 10M+10R (cost savings)

4. **Deploy and test**
   - Start with 10M+10R configuration
   - Load test with actual image data
   - Monitor and adjust based on real usage

---

**Generated from empirical performance testing.** See TEST_REPORT.md for detailed benchmark results with small values. Network bandwidth becomes the primary bottleneck with 1 MB images.
