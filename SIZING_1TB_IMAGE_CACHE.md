# Redis Image Cache Sizing: 1TB Memory, 8K QPS (Kubernetes)

**Your Requirements:**
- Total memory: 1 TB
- QPS: 8,000 requests/second
- p95 latency: < 500 ms
- Data type: Images (1 MB each)
- TTL: 5 minutes (300 seconds)
- High availability: Required
- **Deployment:** Kubernetes cluster

**Based on Test Results:**
- Redis 5/6/7 benchmarked: **190K-220K ops/sec** (256-byte values)
- With 1 MB values: **~3,000-5,000 ops/sec** per pod (network-bound)
- CPU usage at load: **~100%** per pod (single-threaded limit)
- **Pod sizing best practice:** 64GB pods (see POD_SIZING_STRATEGY.md)

---

## Executive Summary

### Recommended Kubernetes Configuration: 16 Masters + 16 Replicas (64GB pods)

**Architecture:** Redis StatefulSet with 64GB pods (recommended sweet spot)

**Per-Pod Specification (Master):**
```yaml
resources:
  requests:
    memory: "77Gi"    # 64 GB usable + 13 GB overhead (20%)
    cpu: "1000m"      # 1 full core (single-threaded limit)
  limits:
    memory: "92Gi"    # 20% buffer above request
    cpu: "1000m"      # NEVER exceed 1 core (single-threaded!)
```

**Per-Pod Specification (Replica):**
```yaml
resources:
  requests:
    memory: "77Gi"    # Same as master for full replication
    cpu: "1000m"      # 1 full core
  limits:
    memory: "92Gi"
    cpu: "1000m"
```

**Cluster-Wide Totals:**
```
Total Pods: 32 (16 masters + 16 replicas)
Total CPU: 32 cores (1 core per pod × 32 pods)
Total Memory Requests: 2.46 TB (77 GB × 32 pods)
Total Memory Limits: 2.94 TB (92 GB × 32 pods)
Total Usable Memory: 1.024 TB across 16 masters (64 GB × 16)
Total PVC Storage: 2.46 TB (77 GB × 32 pods, if persistence enabled)

Expected Performance:
  - QPS capacity: 48,000-80,000 ops/sec (16 pods × 3-5K ops/sec each)
  - Your need: 8,000 ops/sec (6-10x headroom) ✅
  - p95 latency: < 25 ms (20x better than target) ✅
  - Network: 10+ Gbps per pod (320+ Gbps aggregate)
  - Failover time: ~60 seconds per pod ✅

Node Requirements:
  - Minimum nodes: 8 (4 pods per node for balanced distribution)
  - Per-node capacity: 4+ cores, 400+ GB RAM
  - Network: 40+ Gbps per node

Why 64GB pods?
  ✅ Fast failover (~60 seconds)
  ✅ Reasonable blast radius (6.25% capacity loss per pod)
  ✅ Industry-standard size
  ✅ Balanced management complexity
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

### Option 1: Recommended - 16 Masters + 16 Replicas (64GB pods) ✅

**Why 16 masters with 64GB each?**
- Distributes 1 TB across 16 nodes = 64 GB per master
- 64 GB is the **industry-recommended pod size** (see POD_SIZING_STRATEGY.md)
- Fast failover: ~60 seconds per pod
- Small blast radius: 6.25% capacity loss per pod failure
- Each master handles ~500 req/sec (very comfortable)

**Kubernetes StatefulSet Configuration:**

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis-master
spec:
  serviceName: redis-master
  replicas: 16
  selector:
    matchLabels:
      app: redis
      role: master
  template:
    metadata:
      labels:
        app: redis
        role: master
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        ports:
        - containerPort: 6379
          name: redis
        - containerPort: 16379
          name: cluster-bus
        resources:
          requests:
            memory: "77Gi"   # 64 GB usable + 13 GB overhead
            cpu: "1000m"     # 1 full core (single-threaded)
          limits:
            memory: "92Gi"   # 20% buffer
            cpu: "1000m"     # NEVER exceed 1 core!
        command:
        - redis-server
        - --cluster-enabled
        - --cluster-config-file
        - /data/nodes.conf
        - --maxmemory
        - 64gb
        - --maxmemory-policy
        - allkeys-lru
        - --save
        - ""
        - --appendonly
        - "no"
        volumeMounts:
        - name: redis-data
          mountPath: /data
  volumeClaimTemplates:
  - metadata:
      name: redis-data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 77Gi
```

**Cluster Totals:**
```
Total Pods: 32 (16 masters + 16 replicas)
Total CPU: 32 cores
Total Memory Requests: 2.46 TB
Total Memory Limits: 2.94 TB
Total Usable Memory: 1.024 TB
Total PVC: 2.46 TB

QPS Capacity: 48K-80K ops/sec
Your Need: 8,000 ops/sec ✅
```

---

### Option 2: Cost-Optimized - 8 Masters + 8 Replicas (128GB pods)

**If cost is more important than failover speed:**

**Kubernetes Pod Specification:**

```yaml
resources:
  requests:
    memory: "154Gi"  # 128 GB usable + 26 GB overhead
    cpu: "1000m"     # 1 full core
  limits:
    memory: "185Gi"  # 20% buffer
    cpu: "1000m"
```

**Cluster Totals:**
```
Total Pods: 16 (8 masters + 8 replicas)
Total CPU: 16 cores (50% less than Option 1)
Total Memory Requests: 2.46 TB
Total Memory Limits: 2.96 TB
Total Usable Memory: 1.024 TB
Total PVC: 2.46 TB

QPS Capacity: 24K-40K ops/sec
Your Need: 8,000 ops/sec ✅
Failover Time: ~110 seconds per pod (vs 60 sec for 64GB)
```

**Trade-offs:**
- ✅ **50% fewer CPU cores** (16 vs 32) - significant cost savings
- ✅ **Fewer pods to manage** (16 vs 32)
- ✅ **Lower operational overhead**
- ❌ **Slower failover** (110s vs 60s)
- ❌ **Larger blast radius** (12.5% vs 6.25%)
- ❌ **Less granular scaling** (128GB increments vs 64GB)

---

## Performance Analysis

### QPS Capacity

With 1 MB images, throughput is **network-bound**, not CPU-bound.

**Per pod capacity (1 MB values):**
- 10 Gbps network: ~1,250 ops/sec
- 25 Gbps network: ~3,000 ops/sec
- 40 Gbps network: ~5,000 ops/sec

**Option 1: Cluster capacity (16 masters, 64GB pods):**

| Network Speed | Per Master | Total Cluster (16M) | Meets 8K QPS? |
|---------------|------------|---------------------|---------------|
| 10 Gbps | ~1,250 ops/sec | ~20,000 ops/sec | ✅ 2.5x headroom |
| 25 Gbps | ~3,000 ops/sec | ~48,000 ops/sec | ✅ 6.0x headroom |
| 40 Gbps | ~5,000 ops/sec | ~80,000 ops/sec | ✅ 10x headroom |

**Option 2: Cluster capacity (8 masters, 128GB pods):**

| Network Speed | Per Master | Total Cluster (8M) | Meets 8K QPS? |
|---------------|------------|---------------------|---------------|
| 10 Gbps | ~1,250 ops/sec | ~10,000 ops/sec | ✅ 1.25x headroom |
| 25 Gbps | ~3,000 ops/sec | ~24,000 ops/sec | ✅ 3.0x headroom |
| 40 Gbps | ~5,000 ops/sec | ~40,000 ops/sec | ✅ 5.0x headroom |

**Recommendation:** Use 10-25 Gbps network interfaces. Both options meet 8K QPS requirement comfortably.

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

**Option 1: Per pod (16 masters, 64GB pods):**
```
8 GB/sec ÷ 16 = 500 MB/sec = 4.0 Gbps per master
With replication: ~600 MB/sec = 4.8 Gbps per master

10 Gbps network interfaces are more than sufficient ✅
Lower network load per pod (better distribution)
```

**Option 2: Per pod (8 masters, 128GB pods):**
```
8 GB/sec ÷ 8 = 1 GB/sec = 8.0 Gbps per master
With replication: ~1.25 GB/sec = 10 Gbps per master

10 Gbps network interfaces are at capacity ⚠️
25 Gbps recommended for headroom
```

---

## Recommended Kubernetes Deployment

### Option 1: Recommended - 16M + 16R (64GB pods) ✅

**Complete StatefulSet Configuration:**

```yaml
---
# Service for Redis masters
apiVersion: v1
kind: Service
metadata:
  name: redis-master
  labels:
    app: redis
    role: master
spec:
  clusterIP: None  # Headless service
  ports:
  - port: 6379
    targetPort: 6379
    name: redis
  - port: 16379
    targetPort: 16379
    name: cluster-bus
  selector:
    app: redis
    role: master
---
# StatefulSet for Redis masters
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis-master
spec:
  serviceName: redis-master
  replicas: 16
  selector:
    matchLabels:
      app: redis
      role: master
  template:
    metadata:
      labels:
        app: redis
        role: master
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        ports:
        - containerPort: 6379
          name: redis
        - containerPort: 16379
          name: cluster-bus
        resources:
          requests:
            memory: "77Gi"
            cpu: "1000m"
          limits:
            memory: "92Gi"
            cpu: "1000m"
        command:
        - redis-server
        args:
        - --cluster-enabled
        - "yes"
        - --cluster-config-file
        - /data/nodes.conf
        - --maxmemory
        - 64gb
        - --maxmemory-policy
        - allkeys-lru
        - --save
        - ""
        - --appendonly
        - "no"
        volumeMounts:
        - name: redis-data
          mountPath: /data
  volumeClaimTemplates:
  - metadata:
      name: redis-data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: fast-ssd  # Use your storage class
      resources:
        requests:
          storage: 77Gi
---
# Service for Redis replicas
apiVersion: v1
kind: Service
metadata:
  name: redis-replica
  labels:
    app: redis
    role: replica
spec:
  clusterIP: None
  ports:
  - port: 6379
    targetPort: 6379
    name: redis
  - port: 16379
    targetPort: 16379
    name: cluster-bus
  selector:
    app: redis
    role: replica
---
# StatefulSet for Redis replicas (identical to masters)
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis-replica
spec:
  serviceName: redis-replica
  replicas: 16
  selector:
    matchLabels:
      app: redis
      role: replica
  template:
    metadata:
      labels:
        app: redis
        role: replica
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        ports:
        - containerPort: 6379
          name: redis
        - containerPort: 16379
          name: cluster-bus
        resources:
          requests:
            memory: "77Gi"
            cpu: "1000m"
          limits:
            memory: "92Gi"
            cpu: "1000m"
        command:
        - redis-server
        args:
        - --cluster-enabled
        - "yes"
        - --cluster-config-file
        - /data/nodes.conf
        - --maxmemory
        - 64gb
        - --maxmemory-policy
        - allkeys-lru
        - --save
        - ""
        - --appendonly
        - "no"
        volumeMounts:
        - name: redis-data
          mountPath: /data
  volumeClaimTemplates:
  - metadata:
      name: redis-data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      storageClassName: fast-ssd
      resources:
        requests:
          storage: 77Gi
```

**Resource summary:**
- Total Pods: 32 (16M + 16R)
- Total CPU: 32 cores
- Total Memory Requests: 2.46 TB
- Total Memory Limits: 2.94 TB
- Total PVC: 2.46 TB
- Network: 10 Gbps per pod (320 Gbps aggregate)
- Failover time: ~60 seconds

---

### Option 2: Cost-Optimized - 8M + 8R (128GB pods)

**Modify the StatefulSet to use:**
```yaml
spec:
  replicas: 8  # Instead of 16
  template:
    spec:
      containers:
      - name: redis
        resources:
          requests:
            memory: "154Gi"  # Instead of 77Gi
            cpu: "1000m"
          limits:
            memory: "185Gi"  # Instead of 92Gi
            cpu: "1000m"
        args:
        - --maxmemory
        - 128gb  # Instead of 64gb
```

**Resource summary:**
- Total Pods: 16 (8M + 8R)
- Total CPU: 16 cores (50% savings)
- Total Memory Requests: 2.46 TB
- Total Memory Limits: 2.96 TB
- Total PVC: 2.46 TB
- Network: 25 Gbps per pod recommended
- Failover time: ~110 seconds

---

## Configuration Comparison

| Metric | 16M+16R (64GB pods) ✅ | 8M+8R (128GB pods) |
|--------|----------------------|-----------------|
| **Total pods** | 32 | 16 |
| **Total CPU cores** | 32 cores | 16 cores (50% savings) |
| **Memory per master** | 64 GB | 128 GB |
| **QPS per master** | ~500 ops/sec | ~1,000 ops/sec |
| **Network per pod** | 10 Gbps sufficient | 25 Gbps recommended |
| **Total QPS capacity** | 48K-80K ops/sec | 24K-40K ops/sec |
| **Failover time** | ~60 seconds | ~110 seconds |
| **Blast radius** | 6.25% per pod | 12.5% per pod |
| **Scaling granularity** | 64 GB increments | 128 GB increments |
| **Cost** | Higher (2x CPU) | Lower (50% CPU savings) |
| **Recommended for** | Production, HA-critical | Stable workloads, cost-optimized |

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

### Monitoring Commands (Kubernetes)

```bash
# Pod status and resource usage
kubectl get pods -l app=redis -o wide
kubectl top pods -l app=redis

# Check Redis memory and evictions (on a specific pod)
kubectl exec redis-master-0 -- redis-cli INFO memory | grep -E "used_memory|evicted_keys|maxmemory"

# Check Redis stats
kubectl exec redis-master-0 -- redis-cli INFO stats | grep -E "total_commands|instantaneous_ops"

# Check cluster health
kubectl exec redis-master-0 -- redis-cli cluster info
kubectl exec redis-master-0 -- redis-cli cluster nodes

# Check TTL expiration
kubectl exec redis-master-0 -- redis-cli INFO keyspace

# Check latency
kubectl exec redis-master-0 -- redis-cli --latency-history

# View logs
kubectl logs redis-master-0 -f
kubectl logs redis-replica-0 -f

# Check PVC usage
kubectl get pvc
kubectl describe pvc redis-data-redis-master-0
```

### Key Metrics to Track

```bash
# Cache hit rate (calculate from stats)
kubectl exec redis-master-0 -- redis-cli INFO stats | grep -E "keyspace_hits|keyspace_misses"

# Calculate hit rate:
# hit_rate = hits / (hits + misses)
# Target: > 80%

# Memory fragmentation
kubectl exec redis-master-0 -- redis-cli INFO memory | grep mem_fragmentation_ratio
# Target: 1.0-1.5

# Expired keys per second
kubectl exec redis-master-0 -- redis-cli INFO stats | grep expired_keys

# Pod restarts (indicator of OOM or crashes)
kubectl get pods -l app=redis --field-selector=status.phase=Running
kubectl describe pod redis-master-0 | grep -i restart
```

---

## Cost Analysis

### Kubernetes Node Pricing (Example: AWS EKS)

**Node type for 64GB pods:** m6i.2xlarge (8 vCPU, 32 GB RAM)
- Fits 1 pod per node (with 77Gi request)
- On-demand: ~$300/month per node
- Reserved (1 year): ~$200/month per node

**Node type for 128GB pods:** m6i.4xlarge (16 vCPU, 64 GB RAM)
- Fits 1 pod per node (with 154Gi request)
- On-demand: ~$600/month per node
- Reserved (1 year): ~$400/month per node

**Option 1: 16M+16R (32 pods, 64GB each):**
- Need: 32 nodes × m6i.2xlarge
- On-demand: 32 × $300 = **$9,600/month** 💰
- Reserved: 32 × $200 = **$6,400/month**

**Option 2: 8M+8R (16 pods, 128GB each):**
- Need: 16 nodes × m6i.4xlarge
- On-demand: 16 × $600 = **$9,600/month** 💰
- Reserved: 16 × $400 = **$6,400/month**

**Same cost!** BUT:
- Option 1 (64GB) gives better HA (faster failover, smaller blast radius)
- Option 2 (128GB) gives operational simplicity (fewer pods)

### Cost Optimization Strategies

1. **Use Kubernetes node autoscaling:**
   - Scale based on actual memory usage
   - Save cost during low-traffic periods

2. **Use reserved instances (1-3 year commitment):**
   - Save 30-40% vs on-demand
   - Recommended for production workloads

3. **Right-size based on actual usage:**
   - Monitor actual memory usage
   - If only using 500 GB, scale down to 8M+8R with 64GB each
   - 16 pods instead of 32 = **50% cost savings**

4. **Use spot instances (non-production only):**
   - Save 60-70% vs on-demand
   - ⚠️ Risk: nodes can be terminated
   - Only suitable for dev/test environments

---

## Implementation Checklist

### Phase 1: Planning
- [ ] Determine expected cache hit rate (affects memory sizing)
- [ ] Choose deployment option (16M+16R with 64GB vs 8M+8R with 128GB)
- [ ] Verify Kubernetes cluster capacity (nodes, CPU, memory)
- [ ] Verify network infrastructure (10-25 Gbps per pod)
- [ ] Plan pod placement (distribute across availability zones)
- [ ] Choose storage class for PVCs (fast-ssd recommended)

### Phase 2: Kubernetes Infrastructure Setup
- [ ] Ensure Kubernetes cluster has sufficient capacity
  - Option 1: 32 nodes with 8+ vCPU, 40+ GB RAM each
  - Option 2: 16 nodes with 16+ vCPU, 80+ GB RAM each
- [ ] Configure StorageClass for fast SSD volumes
- [ ] Set up network policies if needed
- [ ] Configure pod anti-affinity (spread across nodes/zones)
- [ ] Set up monitoring (Prometheus Operator, Grafana)
- [ ] Configure ServiceMonitor for metrics collection

### Phase 3: Redis StatefulSet Deployment
- [ ] Apply Service manifests (redis-master, redis-replica)
- [ ] Apply StatefulSet manifests (masters and replicas)
- [ ] Wait for all pods to be Running (kubectl get pods -w)
- [ ] Verify PVCs are bound (kubectl get pvc)
- [ ] Check pod resource allocation (kubectl top pods)

### Phase 4: Redis Cluster Initialization
- [ ] Get all Redis pod IPs (kubectl get pods -o wide)
- [ ] Create Redis Cluster using redis-cli:
  ```bash
  kubectl exec -it redis-master-0 -- redis-cli --cluster create \
    $(kubectl get pods -l role=master -o jsonpath='{range .items[*]}{.status.podIP}:6379 {end}') \
    $(kubectl get pods -l role=replica -o jsonpath='{range .items[*]}{.status.podIP}:6379 {end}') \
    --cluster-replicas 1
  ```
- [ ] Verify cluster health (redis-cli cluster info)
- [ ] Verify cluster nodes (redis-cli cluster nodes)
- [ ] Test basic operations (SET/GET with 1 MB values)

### Phase 5: Testing & Validation
- [ ] Load test with actual image data (1 MB)
- [ ] Verify network bandwidth during load (kubectl top pods)
- [ ] Measure actual latencies (p50, p95, p99)
- [ ] Test failover (delete a master pod, verify replica promotion)
- [ ] Verify TTL expiration works correctly
- [ ] Test persistent volume behavior

### Phase 6: Application Integration
- [ ] Update application to use Redis Cluster client library
- [ ] Configure connection to headless services (redis-master, redis-replica)
- [ ] Implement proper error handling and retries
- [ ] Add client-side monitoring and metrics
- [ ] Test cache miss scenarios
- [ ] Test connection pooling

### Phase 7: Production Rollout
- [ ] Deploy application with Redis integration to dev/staging
- [ ] Start with low traffic (10-20%)
- [ ] Monitor cache hit rate
- [ ] Monitor memory usage patterns
- [ ] Monitor failover behavior
- [ ] Gradually increase traffic to 100%
- [ ] Fine-tune based on observations
- [ ] Document runbooks for common operations

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

### Recommended Configuration: 16 Masters + 16 Replicas (64GB pods) ✅

**Based on POD_SIZING_STRATEGY.md best practices**

```yaml
Total Pods: 32
Architecture: Redis Cluster on Kubernetes with HA

Per Pod Specification:
  CPU: 1 core (1000m)
  Memory: 77 Gi requests, 92 Gi limits
  Usable Memory: 64 GB
  Network: 10 Gbps minimum
  Storage: 77 Gi PVC (fast-ssd)

Total Cluster Resources:
  Total CPU: 32 cores
  Total Memory Requests: 2.46 TB
  Total Memory Limits: 2.94 TB
  Total Usable Memory: 1.024 TB (across 16 masters)
  Total PVC: 2.46 TB
  Network: 320 Gbps aggregate

Redis Configuration:
  maxmemory: 64gb
  maxmemory-policy: allkeys-lru
  TTL: 300 seconds (5 minutes)
  Persistence: Disabled (cache only)
  Cluster: Enabled
```

### Expected Performance

| Metric | Expected | Your Requirement | Status |
|--------|----------|------------------|--------|
| **QPS capacity** | 48,000-80,000 | 8,000 | ✅ 6-10x headroom |
| **Memory** | 1.024 TB usable | 1 TB | ✅ Perfect |
| **p95 latency** | 5-15 ms | < 500 ms | ✅ 30-100x better |
| **Failover time** | ~60 seconds | N/A | ✅ Fast |
| **High availability** | Yes (16 replicas) | Required | ✅ Full HA |
| **Blast radius** | 6.25% per pod | N/A | ✅ Small |

### Why This Configuration?

1. ✅ **Follows industry best practices:** 64GB pods recommended in POD_SIZING_STRATEGY.md
2. ✅ **Fast failover:** ~60 seconds per pod (vs 110s for 128GB)
3. ✅ **Small blast radius:** Losing one pod = only 6.25% capacity loss
4. ✅ **Right-sized for memory:** 1.024 TB distributed across 16 masters
5. ✅ **Right-sized for QPS:** 6-10x capacity vs requirement (massive headroom)
6. ✅ **Network optimized:** 10 Gbps per pod is more than sufficient (only 4.8 Gbps needed)
7. ✅ **High availability:** Each master has a dedicated replica
8. ✅ **Scalable:** Can add/remove 64GB increments as needed
9. ✅ **Production-proven:** 64GB is the industry-standard pod size

### Alternative: 8M+8R (128GB pods) for Cost Optimization

If HA is less critical and cost is priority, use 128GB pods:
- Total Pods: 16 (50% fewer)
- Total CPU: 16 cores (50% cost savings)
- Failover time: ~110 seconds (slower)
- Blast radius: 12.5% (larger)
- Best for: Stable workloads with infrequent scaling

---

## Next Steps

1. **Review pod sizing strategy**
   - Read POD_SIZING_STRATEGY.md for detailed pod sizing rationale
   - Decide between 64GB (recommended) vs 128GB (cost-optimized) pods

2. **Confirm cache hit rate assumptions**
   - If > 80% hit rate → 1 TB is more than enough
   - If < 50% hit rate → Consider 1.5-2 TB total (scale to 24-32 pods)

3. **Verify Kubernetes cluster capacity**
   - Ensure 32+ nodes available (for 64GB pods option)
   - Or 16+ nodes (for 128GB pods option)
   - Verify network infrastructure: 10+ Gbps per pod

4. **Consider compression**
   - Can reduce memory/bandwidth by 60-80%
   - May allow 8M+8R (16 pods) instead of 16M+16R (32 pods)
   - Test compression overhead vs bandwidth savings

5. **Deploy and test**
   - Start with 16M+16R configuration (64GB pods)
   - Load test with actual image data (1 MB)
   - Monitor memory, network, and failover behavior
   - Adjust based on real usage patterns

---

**Generated from empirical performance testing.** See:
- **TEST_REPORT.md** - Detailed benchmark results (Redis 5/6/7 performance data)
- **POD_SIZING_STRATEGY.md** - Pod memory sizing best practices (64GB recommendation)
- **VERSION_COMPARISON.md** - Redis version comparison analysis

Network bandwidth becomes the primary bottleneck with 1 MB images (not CPU). All Redis versions are single-threaded and CPU-bound for small values but network-bound for large values.
