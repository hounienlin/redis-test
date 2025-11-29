#!/bin/bash

echo "Starting continuous load on Redis..."
echo "Run './monitor-cpu.sh' in another terminal to watch CPU usage"
echo "Press Ctrl+C to stop"
echo ""

docker run --rm -it \
  --network redis-test_redis-net \
  redis:7-alpine \
  sh -c "
    while true; do
      echo 'Running benchmark cycle...';
      redis-benchmark -h redis -p 6379 -t set,get,lpush,lpop -n 100000 -c 50 -d 256 -q;
      sleep 1;
    done
  "
