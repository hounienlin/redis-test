# Redis Cluster Sizing Guide (Kubernetes)

Based on empirical testing of Redis 5/6/7. See TEST_REPORT.md for details.

**Key Findings:**
- Single-threaded: **~100% CPU** per pod (1 core max)
- Throughput: **170K-220K ops/sec** per pod (256-byte values)
- Performance: **< 10%** difference across versions
- **Pod sizing best practice:** 32GB minimum (see POD_SIZING_STRATEGY.md)

---

## Example: 120GB Cluster Sizing

**Requirement:** 120 GB total memory, < 500ms latency

### Recommended: 4 Masters + 4 Replicas (32GB pods)

**Per-Pod Specification:**
```yaml
resources:
  requests:
    memory: "38Gi"   # 32 GB usable + 6 GB overhead
    cpu: "1000m"     # 1 core (single-threaded)
  limits:
    memory: "46Gi"   # 20% buffer
    cpu: "1000m"     # NEVER exceed 1 core
```

**Cluster Totals:**
```
Total Pods: 8 (4 masters + 4 replicas)
Total CPU: 8 cores
Total Memory Requests: 304 GB (38 GB × 8)
Total Memory Limits: 368 GB (46 GB × 8)
Total Usable Memory: 128 GB (32 GB × 4 masters)
Total PVC: 304 GB (if persistence enabled)

Expected Performance:
  - Throughput: ~680K-880K ops/sec (4 masters)
  - Latency p50: < 1 ms
  - Latency p99: < 5 ms (100x better than 500ms target)
  - Failover: ~30 seconds per pod

Node Requirements:
  - Minimum: 3 nodes (2-3 pods per node)
  - Per-node: 3+ cores, 120+ GB RAM
  - Network: 10+ Gbps
```

---

## StatefulSet Configuration

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis-master
spec:
  serviceName: redis-master
  replicas: 4
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
        resources:
          requests:
            memory: "38Gi"
            cpu: "1000m"
          limits:
            memory: "46Gi"
            cpu: "1000m"
        command:
        - redis-server
        args:
        - --cluster-enabled
        - "yes"
        - --maxmemory
        - 32gb
        - --maxmemory-policy
        - allkeys-lru
        volumeMounts:
        - name: redis-data
          mountPath: /data
  volumeClaimTemplates:
  - metadata:
      name: redis-data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 38Gi
```

Repeat for `redis-replica` StatefulSet with `replicas: 4`.

---

## Sizing Quick Reference

| Total Memory | Pod Size | Masters | Replicas | Total Pods | Total CPU |
|--------------|----------|---------|----------|------------|-----------|
| 100-150 GB | 32 GB | 4 | 4 | 8 | 8 cores |
| 200-300 GB | 64 GB | 4 | 4 | 8 | 8 cores |
| 500-700 GB | 64 GB | 8-10 | 8-10 | 16-20 | 16-20 cores |
| 1 TB | 64 GB | 16 | 16 | 32 | 32 cores |

**Rules:**
- **CPU**: Always 1 core per pod (single-threaded)
- **Pod size**: 32GB minimum, 64GB recommended, 128GB for cost optimization
- **HA**: Always use N masters + N replicas
- See POD_SIZING_STRATEGY.md for detailed pod sizing rationale

---

## Monitoring

**Key metrics:**
```bash
# Pod status
kubectl get pods -l app=redis
kubectl top pods -l app=redis

# Redis metrics
kubectl exec redis-master-0 -- redis-cli INFO stats
kubectl exec redis-master-0 -- redis-cli INFO memory
kubectl exec redis-master-0 -- redis-cli cluster info

# Latency
kubectl exec redis-master-0 -- redis-cli --latency-history
```

**Alert thresholds:**
- CPU > 90%
- Memory > 85%
- Latency p99 > 50ms
- Evicted keys > 1000/sec

---

## Reference Documents

- **POD_SIZING_STRATEGY.md** - Pod memory sizing best practices (32GB/64GB/128GB)
- **TEST_REPORT.md** - Redis 5/6/7 performance benchmarks
- **SIZING_1TB_IMAGE_CACHE.md** - Large-scale example (1TB cluster)
- **SIZING_FOR_8K_QPS_1MB.md** - Network-bound workload example
