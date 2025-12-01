# Redis Pod Memory Sizing Strategy for Kubernetes

**Key Question:** Should you deploy 10x 64GB pods or 5x 128GB pods for the same total capacity?

**Based on Empirical Testing:**
- Redis 5, 6, 7 all single-threaded: **1 CPU core per pod maximum**
- Memory is the **only scaling dimension** (CPU is always 1 core)
- Performance: **170K-220K ops/sec** per pod (small values)
- Network-bound: **~3K-5K ops/sec** per pod (1 MB values)

---

## Pod Memory Size Recommendations

### Recommended Pod Sizes

| Pod Size | Use Case | Pros | Cons |
|----------|----------|------|------|
| **16-32 GB** | Development, testing, microservices | Fast failover, minimal blast radius | High overhead %, many pods to manage |
| **32-64 GB** | ✅ **RECOMMENDED** - General purpose | Balanced failover/overhead, proven size | Good for most production workloads |
| **64-128 GB** | Large datasets, fewer pods preferred | Lower overhead %, fewer pods | Slower failover, bigger blast radius |
| **128-256 GB** | Massive datasets, network-bound workloads | Best memory efficiency | Very slow failover, complex operations |
| **> 256 GB** | ❌ **NOT RECOMMENDED** | Minimal overhead | Unacceptable failover time, operational risk |

### Absolute Limits

**Minimum Pod Size:** 8-16 GB
- Below this, Redis overhead becomes too high (> 40%)
- Not cost-effective
- Better to use a managed cache service

**Maximum Pod Size:** 256 GB
- Above this, operational risks outweigh benefits
- Failover time becomes problematic (minutes to hours)
- Memory fragmentation issues increase
- Fork operations (for persistence) take too long

**Sweet Spot:** **32-64 GB per pod** ✅

---

## Detailed Comparison: 64 GB vs 128 GB Pods

### Scenario: 1 TB Total Memory Deployment

#### Option A: Many Small Pods (64 GB each)

**Configuration:**
```yaml
Total Memory: 1 TB
Pod Size: 64 GB usable (77 GB allocated with overhead)
Number of Masters: 16 pods
Number of Replicas: 16 pods
Total Pods: 32

Per-Pod Spec:
  requests:
    memory: "77Gi"
    cpu: "1000m"
  limits:
    memory: "92Gi"
    cpu: "1000m"
```

**Cluster Totals:**
```
Total CPU: 32 cores
Total Memory Requests: 2.46 TB
Total Memory Limits: 2.94 TB
Total PVC: 2.46 TB
```

**Advantages:**
- ✅ **Fast failover:** 64 GB takes 10-30 seconds to replicate
- ✅ **Small blast radius:** Losing one pod = only 6.25% of capacity
- ✅ **Better distribution:** 16 shards = better load balancing
- ✅ **Easier rebalancing:** Smaller shards easier to move
- ✅ **Gradual scaling:** Can add/remove pods with less impact
- ✅ **Node flexibility:** Easier to fit on various node sizes

**Disadvantages:**
- ❌ **More pods to manage:** 32 total pods vs 16
- ❌ **Higher memory overhead:** ~20% overhead per pod
- ❌ **More network connections:** 32 pods = more cluster gossip
- ❌ **Higher CPU usage:** More pods = more CPU for overhead

**Best For:**
- High availability requirements
- Frequent scaling operations
- Heterogeneous node sizes
- Applications sensitive to failover time

---

#### Option B: Fewer Large Pods (128 GB each)

**Configuration:**
```yaml
Total Memory: 1 TB
Pod Size: 128 GB usable (154 GB allocated with overhead)
Number of Masters: 8 pods
Number of Replicas: 8 pods
Total Pods: 16

Per-Pod Spec:
  requests:
    memory: "154Gi"
    cpu: "1000m"
  limits:
    memory: "185Gi"
    cpu: "1000m"
```

**Cluster Totals:**
```
Total CPU: 16 cores
Total Memory Requests: 2.46 TB
Total Memory Limits: 2.96 TB
Total PVC: 2.46 TB
```

**Advantages:**
- ✅ **Fewer pods:** 16 total vs 32 (easier to manage)
- ✅ **Lower overhead %:** ~20% overhead but spread over larger base
- ✅ **Less cluster gossip:** Fewer pods = less protocol overhead
- ✅ **Simpler topology:** Fewer connections to manage
- ✅ **Lower CPU overhead:** Fewer Redis processes

**Disadvantages:**
- ❌ **Slow failover:** 128 GB takes 30-90 seconds to replicate
- ❌ **Large blast radius:** Losing one pod = 12.5% of capacity
- ❌ **Coarse scaling:** Adding/removing 128 GB at a time
- ❌ **Node constraints:** Needs nodes with 185+ GB RAM
- ❌ **Fork operations:** Slower RDB/AOF persistence

**Best For:**
- Stable workloads with infrequent changes
- Cost optimization (fewer pods)
- Large homogeneous nodes
- Less stringent failover requirements

---

## Decision Framework

### Choose SMALLER pods (32-64 GB) when:

1. **High availability is critical**
   - Failover time must be < 30 seconds
   - Cannot tolerate losing > 5% capacity at once

2. **Dynamic scaling required**
   - Frequent autoscaling operations
   - Need fine-grained capacity adjustments

3. **Heterogeneous infrastructure**
   - Mixed node sizes in cluster
   - Need flexibility in pod placement

4. **Development/testing environments**
   - Rapid iteration and testing
   - Cost is less critical than agility

### Choose LARGER pods (64-128 GB) when:

1. **Stable workload**
   - Predictable traffic patterns
   - Infrequent scaling events

2. **Cost optimization priority**
   - Minimize number of pods
   - Reduce operational overhead

3. **Large dataset with low churn**
   - Persistent data (not cache with TTL)
   - Read-heavy workload

4. **Homogeneous infrastructure**
   - All nodes same size (e.g., 256 GB RAM)
   - Simpler resource planning

---

## Best Practices

### General Recommendations

**1. Default to 64 GB pods** for most production workloads
```yaml
resources:
  requests:
    memory: "77Gi"  # 64 GB usable + 13 GB overhead
    cpu: "1000m"
  limits:
    memory: "92Gi"  # 20% buffer
    cpu: "1000m"
```

**2. Use 32 GB pods** for HA-critical systems
```yaml
resources:
  requests:
    memory: "38Gi"  # 32 GB usable + 6 GB overhead
    cpu: "1000m"
  limits:
    memory: "46Gi"
    cpu: "1000m"
```

**3. Use 128 GB pods** only when justified
```yaml
resources:
  requests:
    memory: "154Gi"  # 128 GB usable + 26 GB overhead
    cpu: "1000m"
  limits:
    memory: "185Gi"
    cpu: "1000m"
```

### Sizing Algorithm

**Step 1: Calculate total memory needed**
```python
total_memory = working_set_size * 1.2  # 20% overhead
```

**Step 2: Choose pod size based on priorities**
```python
if ha_critical or frequent_scaling:
    pod_size = 32 * GB  # Small pods
elif standard_production:
    pod_size = 64 * GB  # Medium pods (RECOMMENDED)
elif cost_optimized or stable_workload:
    pod_size = 128 * GB  # Large pods
else:
    pod_size = 64 * GB  # Default to medium
```

**Step 3: Calculate number of pods**
```python
num_masters = ceil(total_memory / pod_size)
num_replicas = num_masters  # 1:1 ratio for HA
total_pods = num_masters + num_replicas
```

**Step 4: Verify constraints**
```python
# Each pod always gets exactly 1 CPU core
total_cpu_cores = total_pods * 1

# Check node capacity
min_node_memory = pod_size * 1.2  # with limits
pods_per_node = floor(node_memory / min_node_memory)
min_nodes = ceil(total_pods / pods_per_node)
```

---

## Real-World Examples

### Example 1: E-commerce Session Store (HA Critical)

**Requirements:**
- 500 GB total memory
- 50,000 QPS
- p99 latency < 10ms
- Failover < 30 seconds

**Recommendation: 32 GB pods**
```
Pod Size: 32 GB usable (38 GB allocated)
Masters: 16 pods
Replicas: 16 pods
Total: 32 pods, 32 CPU cores, 1.22 TB memory

Why:
- Fast failover: 32 GB replicates in ~20 seconds
- Small blast radius: 6.25% capacity loss per pod
- HA critical: E-commerce cannot tolerate downtime
```

### Example 2: Analytics Cache (Stable Workload)

**Requirements:**
- 2 TB total memory
- 10,000 QPS
- p95 latency < 100ms
- Failover < 2 minutes acceptable

**Recommendation: 128 GB pods**
```
Pod Size: 128 GB usable (154 GB allocated)
Masters: 16 pods
Replicas: 16 pods
Total: 32 pods, 32 CPU cores, 4.93 TB memory

Why:
- Fewer pods: Easier to manage
- Stable workload: Infrequent scaling
- Cost efficient: Lower overhead percentage
- Acceptable failover: 90 seconds is fine
```

### Example 3: Image Cache (Network-Bound)

**Requirements:**
- 1 TB total memory
- 8,000 QPS
- 1 MB values (network-bound)
- HA required

**Recommendation: 64 GB pods**
```
Pod Size: 64 GB usable (77 GB allocated)
Masters: 16 pods
Replicas: 16 pods
Total: 32 pods, 32 CPU cores, 2.46 TB memory

Why:
- Network-bound: ~3-5K ops/sec per pod
- Need 16 masters for 8K QPS (16 × 500-1000 ops each)
- 64 GB balances failover speed and management
- Good distribution for network load
```

---

## Memory Overhead Deep Dive

### Overhead Components

Redis memory overhead includes:

1. **Data Structure Overhead** (~10-15%)
   - Pointers, metadata, internal structures
   - Doesn't scale with value size

2. **Memory Fragmentation** (~10-20%)
   - Varies with workload pattern
   - Worse with many small allocations
   - Larger pods = potentially more fragmentation

3. **Replication Buffer** (~5-10%)
   - For master-replica sync
   - Proportional to write rate, not pod size

4. **Connection Buffers** (~2-5%)
   - Fixed per connection
   - More significant for smaller pods

### Overhead by Pod Size

| Pod Size | Data | Overhead | Total Allocated | Overhead % |
|----------|------|----------|-----------------|------------|
| 16 GB | 16 GB | ~6-8 GB | 22-24 GB | ~37-50% |
| 32 GB | 32 GB | ~6-10 GB | 38-42 GB | ~19-31% |
| 64 GB | 64 GB | ~13-20 GB | 77-84 GB | ~20-31% |
| 128 GB | 128 GB | ~26-38 GB | 154-166 GB | ~20-30% |
| 256 GB | 256 GB | ~51-77 GB | 307-333 GB | ~20-30% |

**Key Insight:** Overhead **percentage stabilizes around 20-30%** for pods ≥ 32 GB

---

## Failover Time Analysis

### Replication Time Estimates

Based on 10 Gbps network (1.25 GB/sec transfer rate):

| Pod Size | Transfer Time | Initialization | Total Failover | Acceptable? |
|----------|---------------|----------------|----------------|-------------|
| 16 GB | 13 seconds | 2-5 sec | **15-18 sec** | ✅ Excellent |
| 32 GB | 26 seconds | 2-5 sec | **28-31 sec** | ✅ Very Good |
| 64 GB | 51 seconds | 3-7 sec | **54-58 sec** | ✅ Good |
| 128 GB | 102 seconds | 5-10 sec | **107-112 sec** | ⚠️ Acceptable |
| 256 GB | 205 seconds | 10-20 sec | **215-225 sec** | ❌ Too Slow |

**Recommendation:** Stay ≤ 128 GB if failover matters

---

## Cost Analysis

### Infrastructure Costs

**Scenario: 1 TB deployment with HA**

| Strategy | Pods | CPU Cores | Memory (limits) | Node Count | Monthly Cost* |
|----------|------|-----------|-----------------|------------|---------------|
| 32 GB pods | 32 | 32 | 1.47 TB | 8 nodes (4 pods/node) | $2,560 |
| 64 GB pods | 16 | 16 | 1.47 TB | 4 nodes (4 pods/node) | $1,280 |
| 128 GB pods | 8 | 8 | 1.48 TB | 2 nodes (4 pods/node) | $640 |

*Approximate costs based on $80/month per vCore on typical cloud provider

**Key Finding:** Larger pods = ~50% cost reduction per doubling

**BUT:** Consider operational costs:
- Downtime during failover
- Engineering time for pod management
- Incident response complexity

---

## Final Recommendation

### Production Standard: **64 GB Pods** ✅

**Why 64 GB is the sweet spot:**

1. ✅ **Fast failover:** ~60 seconds (acceptable for most use cases)
2. ✅ **Reasonable blast radius:** ~6-12% capacity loss per pod failure
3. ✅ **Balanced overhead:** ~20-25% (not excessive)
4. ✅ **Manageable pod count:** Not too many to overwhelm operations
5. ✅ **Node flexibility:** Fits well on common node sizes (128-256 GB)
6. ✅ **Scaling granularity:** Can add/remove 64 GB increments
7. ✅ **Proven in production:** Industry-standard size

**Decision Tree:**

```
START: What's your primary concern?
│
├─ HA / Failover critical?
│  └─ Use 32 GB pods
│
├─ Cost optimization priority?
│  └─ Use 128 GB pods (if failover acceptable)
│
├─ Balanced production workload?
│  └─ Use 64 GB pods ✅ RECOMMENDED
│
└─ Not sure?
   └─ Use 64 GB pods ✅ DEFAULT
```

---

## Validation Checklist

Before finalizing pod size, verify:

- [ ] Failover time acceptable for SLA? (calculate: pod_size_gb / 1.25 sec)
- [ ] Blast radius acceptable? (calculate: 1 / num_masters × 100%)
- [ ] Node size can fit pods? (pod_memory_limit × 4 ≤ node_memory)
- [ ] Scaling granularity appropriate? (can add/remove pod_size increments)
- [ ] Cost budget met? (total_pods × cost_per_pod ≤ budget)
- [ ] CPU sufficient? (total_pods × 1_core ≥ qps_requirement)

---

## Summary Table

| Pod Size | HA | Cost | Ops Complexity | Failover | Best For |
|----------|----|----|----------------|----------|----------|
| **32 GB** | ⭐⭐⭐⭐⭐ | 💰💰💰 | ⚙️⚙️⚙️ | 30s | Mission-critical HA |
| **64 GB** | ⭐⭐⭐⭐ | 💰💰 | ⚙️⚙️ | 60s | **RECOMMENDED** |
| **128 GB** | ⭐⭐⭐ | 💰 | ⚙️ | 110s | Stable, cost-optimized |
| **256 GB** | ⭐⭐ | 💰 | ⚙️ | 220s | Special cases only |

**Remember:** CPU is always **1 core per pod**. Memory is the **only scaling dimension**.

---

**Document Version:** 1.0
**Last Updated:** 2025-12-01
**Based On:** Redis 5/6/7 empirical testing (TEST_REPORT.md)
