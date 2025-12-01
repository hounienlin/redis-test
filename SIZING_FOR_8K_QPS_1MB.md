# Redis Cluster Sizing: 8K QPS with 1MB Values (Kubernetes)

**Your Specific Requirements:**
- QPS: 8,000 queries/second
- Value size: 1 MB per request
- Total memory: 120 GB
- High availability: Required
- Latency target: 500 ms
- **Deployment:** Kubernetes cluster

**Based on Test Results:**
- Redis 5/6/7 benchmarked: **190K-220K ops/sec** (256-byte values)
- With 1 MB values: **~3,000-5,000 ops/sec** per instance (network-bound)
- CPU usage at load: **~100%** per pod (single-threaded limit)

---

## Executive Summary

### Recommended Kubernetes Configuration

**Architecture:** Redis StatefulSet with 3 masters + 3 replicas

**Per-Pod Specification (Master):**
```yaml
resources:
  requests:
    memory: "45Gi"   # 40 GB usable + 5 GB overhead
    cpu: "1000m"     # 1 full core (single-threaded limit)
  limits:
    memory: "54Gi"   # 20% buffer above request
    cpu: "1000m"     # NEVER exceed 1 core (single-threaded!)
```

**Per-Pod Specification (Replica):**
```yaml
resources:
  requests:
    memory: "45Gi"   # Same as master
    cpu: "1000m"     # 1 full core
  limits:
    memory: "54Gi"
    cpu: "1000m"
```

**Cluster-Wide Totals:**
```
Total Pods: 6 (3 masters + 3 replicas)
Total CPU: 6 cores (1 core per pod × 6 pods)
Total Memory Requests: 270 GB (45 GB × 6 pods)
Total Memory Limits: 324 GB (54 GB × 6 pods)
Total PVC Storage: 270 GB (45 GB × 6 pods, if persistence enabled)

Expected Performance: 9,000-15,000 QPS capacity
Network Required: 64 Gbps aggregate (10+ Gbps per pod)

Node Requirements:
- Minimum nodes: 3 (2 pods per node for HA)
- Per-node capacity: 2+ cores, 110+ GB RAM
- Network: 25+ Gbps between nodes
```

**Key Finding:** You're significantly **over-provisioned** for QPS, but **network bandwidth is your real bottleneck**.

---

## Why 10 Instances is Too Many

### QPS Analysis

Your requirement: **8,000 QPS**
Our benchmark: **~190,000 ops/sec** with 256-byte values

**However**, with 1 MB values, throughput is limited by network bandwidth:

| Value Size | Throughput/Instance | Limiting Factor |
|------------|---------------------|-----------------|
| 256 bytes (our test) | ~190,000 ops/sec | CPU-bound |
| 1 KB | ~80,000 ops/sec | CPU + Network |
| 10 KB | ~15,000 ops/sec | Network-bound |
| 100 KB | ~2,000 ops/sec | Network-bound |
| **1 MB** | **~1,500-5,000 ops/sec** | **Network-bound** |

**With 1 MB values:**
- Per-instance capacity: ~3,000-5,000 QPS (conservative estimate)
- Your need: 8,000 QPS
- **Required instances: 2-3 masters** (with HA: 4-6 total)

**Conclusion:** 10 instances is **3-5x over-provisioned** for your QPS needs.

---

## Revised Sizing Calculation

### Option 1: Minimal HA Setup (Recommended)

**Configuration:**
```
3 master nodes
3 replica nodes (one per master)
Total: 6 instances
```

**Per-Pod Specs (Kubernetes):**
```yaml
# Master Pod
apiVersion: v1
kind: Pod
metadata:
  name: redis-master-0
spec:
  containers:
  - name: redis
    image: redis:7-alpine
    resources:
      requests:
        memory: "45Gi"     # Total allocation
        cpu: "1000m"       # 1 core (single-threaded)
      limits:
        memory: "54Gi"     # 20% buffer
        cpu: "1000m"       # Max 1 core
    command: ["redis-server", "--maxmemory", "40gb", "--maxmemory-policy", "allkeys-lru"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: redis-pvc-master-0

# Each master holds 40 GB usable
# 3 masters × 40 GB = 120 GB total ✓
```

**Why this works:**
- ✅ 120 GB total usable memory (3 × 40 GB)
- ✅ ~9,000-15,000 QPS capacity (3 × 3,000-5,000)
- ✅ High availability (can lose 1 master)
- ✅ 50% cost reduction (6 vs 10 instances)

**Network bandwidth:**
```
8,000 QPS × 1 MB = 8 GB/sec per direction
Total with replication: ~16 GB/sec (128 Gbps)
Per instance: ~5.3 GB/sec (42 Gbps) writes
```

### Option 2: Conservative HA Setup

**Configuration:**
```
4 master nodes
4 replica nodes
Total: 8 instances
```

**Per-Instance Specs:**
```yaml
redis-master-X:
  cpus: 1
  memory: 32GB        # Total allocation
  maxmemory: 30GB     # Usable by Redis

  # Each master holds 30 GB
  # 4 masters × 30 GB = 120 GB total ✓
```

**Why this option:**
- ✅ 120 GB total usable memory (4 × 30 GB)
- ✅ ~12,000-20,000 QPS capacity (4 × 3,000-5,000)
- ✅ More HA resilience (can lose 2 masters if using cluster)
- ✅ More headroom for traffic spikes
- Better distribution reduces per-instance network load

### Option 3: Your Original 10 Instances (Over-provisioned)

Only use this if:
- You expect significant QPS growth (8K → 30K+)
- You want maximum redundancy
- Cost is not a concern
- You want minimal per-instance resource utilization

---

## Detailed Comparison

| Configuration | Instances | Memory/Instance | Total Memory | QPS Capacity | Cost Efficiency |
|---------------|-----------|-----------------|--------------|--------------|-----------------|
| **Minimal (Recommended)** | 6 (3M+3R) | 45 GB | 135 GB | ~12,000 | ⭐⭐⭐⭐⭐ |
| **Conservative** | 8 (4M+4R) | 32 GB | 128 GB | ~16,000 | ⭐⭐⭐⭐ |
| **Original** | 10 (5M+5R) | 16 GB | 80 GB | ~20,000 | ⭐⭐ |

---

## Network Bandwidth Analysis (CRITICAL!)

### Your Network Requirements

With 8,000 QPS and 1 MB values:

**Read-only workload:**
```
8,000 reads/sec × 1 MB = 8 GB/sec outbound (64 Gbps)
```

**Write-only workload:**
```
8,000 writes/sec × 1 MB = 8 GB/sec inbound (64 Gbps)
+ Replication to replica = 8 GB/sec × 3 = 24 GB/sec (192 Gbps)
Total: 32 GB/sec (256 Gbps)
```

**Mixed workload (50/50):**
```
4,000 reads × 1 MB = 4 GB/sec outbound
4,000 writes × 1 MB = 4 GB/sec inbound + 12 GB/sec replication
Total: ~20 GB/sec (160 Gbps)
```

### Network Requirements Per Instance (3-master setup)

```
Per master: ~2,700 QPS
Network load: ~2.7 GB/sec (21.6 Gbps)

Required network interface: 25 Gbps or higher
```

⚠️ **Critical Infrastructure Requirement:**
- Each Redis instance needs **25+ Gbps network interface**
- 10 Gbps interfaces will bottleneck at ~1,250 QPS with 1 MB values
- Verify your infrastructure supports this bandwidth!

---

## Latency Expectations with 1 MB Values

Our tests showed latencies with 256-byte values. With 1 MB values:

| Metric | 256 bytes (tested) | 1 MB (estimated) |
|--------|-------------------|------------------|
| **Network transfer time** | ~0.02 ms (1 Gbps) | ~8 ms (1 Gbps) |
| **Redis processing** | 0.1-0.3 ms | 0.1-0.5 ms |
| **Total latency (p50)** | ~0.2 ms | **~8-10 ms** |
| **Total latency (p99)** | ~0.5 ms | **~15-25 ms** |

**Your 500 ms target:** ✅ Still easily achievable (20-50x margin)

**Network speed matters:**
- 1 Gbps network: ~8 ms transfer time for 1 MB
- 10 Gbps network: ~0.8 ms transfer time for 1 MB
- 25 Gbps network: ~0.32 ms transfer time for 1 MB

---

## Final Recommendation

### Recommended: 6-Instance Cluster (3 Masters + 3 Replicas)

```yaml
version: '3.8'

services:
  # Master Nodes
  redis-master-1:
    image: redis:7-alpine
    container_name: redis-master-1
    cpus: 1
    mem_limit: 45g
    command: >
      redis-server
      --port 7000
      --cluster-enabled yes
      --cluster-config-file nodes.conf
      --cluster-node-timeout 5000
      --maxmemory 40gb
      --maxmemory-policy allkeys-lru
      --save ""
      --appendonly no
    ports:
      - "7000:7000"
    networks:
      - redis-cluster

  redis-master-2:
    image: redis:7-alpine
    container_name: redis-master-2
    cpus: 1
    mem_limit: 45g
    command: >
      redis-server
      --port 7001
      --cluster-enabled yes
      --cluster-config-file nodes.conf
      --cluster-node-timeout 5000
      --maxmemory 40gb
      --maxmemory-policy allkeys-lru
      --save ""
      --appendonly no
    ports:
      - "7001:7001"
    networks:
      - redis-cluster

  redis-master-3:
    image: redis:7-alpine
    container_name: redis-master-3
    cpus: 1
    mem_limit: 45g
    command: >
      redis-server
      --port 7002
      --cluster-enabled yes
      --cluster-config-file nodes.conf
      --cluster-node-timeout 5000
      --maxmemory 40gb
      --maxmemory-policy allkeys-lru
      --save ""
      --appendonly no
    ports:
      - "7002:7002"
    networks:
      - redis-cluster

  # Replica Nodes
  redis-replica-1:
    image: redis:7-alpine
    container_name: redis-replica-1
    cpus: 1
    mem_limit: 45g
    command: >
      redis-server
      --port 7003
      --cluster-enabled yes
      --cluster-config-file nodes.conf
      --cluster-node-timeout 5000
      --maxmemory 40gb
      --maxmemory-policy allkeys-lru
      --save ""
      --appendonly no
    ports:
      - "7003:7003"
    networks:
      - redis-cluster

  redis-replica-2:
    image: redis:7-alpine
    container_name: redis-replica-2
    cpus: 1
    mem_limit: 45g
    command: >
      redis-server
      --port 7004
      --cluster-enabled yes
      --cluster-config-file nodes.conf
      --cluster-node-timeout 5000
      --maxmemory 40gb
      --maxmemory-policy allkeys-lru
      --save ""
      --appendonly no
    ports:
      - "7004:7004"
    networks:
      - redis-cluster

  redis-replica-3:
    image: redis:7-alpine
    container_name: redis-replica-3
    cpus: 1
    mem_limit: 45g
    command: >
      redis-server
      --port 7005
      --cluster-enabled yes
      --cluster-config-file nodes.conf
      --cluster-node-timeout 5000
      --maxmemory 40gb
      --maxmemory-policy allkeys-lru
      --save ""
      --appendonly no
    ports:
      - "7005:7005"
    networks:
      - redis-cluster

networks:
  redis-cluster:
    driver: bridge
```

**After starting, create the cluster:**
```bash
docker exec -it redis-master-1 redis-cli --cluster create \
  redis-master-1:7000 \
  redis-master-2:7001 \
  redis-master-3:7002 \
  redis-replica-1:7003 \
  redis-replica-2:7004 \
  redis-replica-3:7005 \
  --cluster-replicas 1
```

---

## Resource Summary

### Option 1: Recommended (6 instances)

| Resource | Per Instance | Total Cluster |
|----------|--------------|---------------|
| **CPU** | 1 vCore | **6 vCores** |
| **Memory (allocated)** | 45 GB | **270 GB** |
| **Memory (usable)** | 40 GB | **120 GB** ✅ |
| **Network** | 25 Gbps | 25 Gbps × 6 |
| **QPS capacity** | ~2,700 | **~12,000** ✅ |

### Option 2: Conservative (8 instances)

| Resource | Per Instance | Total Cluster |
|----------|--------------|---------------|
| **CPU** | 1 vCore | **8 vCores** |
| **Memory (allocated)** | 32 GB | **256 GB** |
| **Memory (usable)** | 30 GB | **120 GB** ✅ |
| **Network** | 25 Gbps | 25 Gbps × 8 |
| **QPS capacity** | ~2,000 | **~16,000** ✅ |

---

## Important Considerations

### 1. Is Redis the Right Choice for 1 MB Values?

**Redis is optimized for:**
- Small to medium values (< 100 KB)
- Sub-millisecond latencies
- Very high QPS

**For 1 MB values, consider:**
- **Object storage** (S3, MinIO) for large blobs
- **CDN** for frequently accessed large objects
- **Hybrid approach:**
  - Store metadata in Redis (< 1 KB)
  - Store actual 1 MB data in object storage
  - Redis returns pre-signed URLs

**If you must use Redis for 1 MB values:**
- Your current approach works
- Just be aware of network bandwidth constraints
- Consider compression (can reduce network load 3-10x)

### 2. Network Bandwidth is Your Bottleneck

**Verify your infrastructure supports:**
- 25+ Gbps network interfaces per host
- Low-latency network switches
- Sufficient aggregate bandwidth

**Without adequate network:**
- You'll bottleneck at ~1,000-2,000 QPS (with 10 Gbps)
- Latencies will increase significantly
- CPU will be underutilized

### 3. Consider Compression

**Enable Redis compression or compress values client-side:**

```python
# Example: Compress before storing
import zlib

# Compress (can achieve 3-10x reduction for text/JSON)
compressed = zlib.compress(large_value)
redis.set(key, compressed)

# Decompress on retrieval
compressed = redis.get(key)
value = zlib.decompress(compressed)
```

**Benefits:**
- Reduce 1 MB → 100-300 KB (typical for JSON/text)
- 3-10x less network bandwidth
- 3-10x higher effective QPS
- Lower latency due to less network transfer time

**Trade-offs:**
- CPU overhead for compression/decompression (usually negligible)
- Client-side implementation required

---

## Cost Comparison

Assuming cloud provider pricing (example):
- vCore: $50/month
- Memory (GB): $5/month

| Configuration | vCores | Memory | Monthly Cost | Savings |
|---------------|--------|---------|--------------|---------|
| **6 instances** | 6 | 270 GB | **$1,650** | **50% vs 10** |
| **8 instances** | 8 | 256 GB | **$1,680** | **43% vs 10** |
| **10 instances** | 10 | 160 GB | **$1,300** | Baseline |

Wait, 10 instances would actually be cheaper for memory! Let me recalculate:

| Configuration | vCores | Memory | Monthly Cost |
|---------------|--------|---------|--------------|
| **6 instances (3M+3R)** | 6 | 270 GB | $300 + $1,350 = **$1,650** |
| **8 instances (4M+4R)** | 8 | 256 GB | $400 + $1,280 = **$1,680** |
| **10 instances (5M+5R)** | 10 | 160 GB | $500 + $800 = **$1,300** ✅ Cheapest |

**Interesting finding:** 10 instances is actually cheaper because each instance needs less memory!

**Revised recommendation:** Stick with 10 instances for cost optimization!

---

## Updated Final Recommendation

### Use Your Original 10-Instance Plan!

**Configuration:**
```
5 master nodes (12 GB each = 60 GB)
5 replica nodes (12 GB each = 60 GB)
Total: 10 instances, 120 GB usable
```

**Per-Instance:**
```yaml
redis-master/replica-X:
  cpus: 1
  memory: 16GB
  maxmemory: 12GB
  network: 25 Gbps (ensure infrastructure supports this!)
```

**Benefits:**
- ✅ Cheapest option ($1,300/month)
- ✅ Easiest memory distribution (12 GB × 10)
- ✅ Best redundancy (5-way replication possible)
- ✅ Lowest per-instance network load (~1.6 GB/sec)
- ✅ Most headroom for growth

**QPS Capacity:**
```
5 masters × 3,000-5,000 QPS = 15,000-25,000 QPS
Your need: 8,000 QPS
Headroom: 87%-200% ✅
```

---

## Action Items

1. **Verify network infrastructure:**
   - [ ] Confirm each host has 25+ Gbps network interface
   - [ ] Test actual network throughput between instances
   - [ ] Monitor network utilization during load testing

2. **Consider compression:**
   - [ ] Test compression ratio on your 1 MB values
   - [ ] Implement client-side compression if beneficial
   - [ ] Re-measure QPS capacity with compressed values

3. **Deploy with monitoring:**
   - [ ] Monitor network bandwidth (most critical metric)
   - [ ] Monitor CPU usage (should be 20-40%, not 100%)
   - [ ] Monitor memory usage
   - [ ] Monitor latency (should be < 25 ms p99)

4. **Load test before production:**
   - [ ] Test with actual 1 MB values
   - [ ] Verify 8,000 QPS capacity
   - [ ] Measure actual latencies
   - [ ] Identify real bottleneck (likely network)

---

## Summary

**Your original 10-instance plan is actually optimal!**

- ✅ Cost-effective (cheapest option)
- ✅ Meets QPS requirements (8K with 200% headroom)
- ✅ Meets memory requirements (120 GB)
- ✅ Provides high availability (5 masters + 5 replicas)
- ✅ Meets latency requirements (< 25 ms vs 500 ms target)

**Critical success factor:**
⚠️ **Ensure 25+ Gbps network interfaces** per instance
Without adequate network bandwidth, you'll bottleneck at ~2,000 QPS.

**Next steps:**
1. Verify network infrastructure can support 64 Gbps (8 GB/sec)
2. Consider compression to reduce network load
3. Deploy and load test with actual 1 MB values
