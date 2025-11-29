#!/bin/bash

echo "Monitoring Redis CPU usage..."
echo "Press Ctrl+C to stop"
echo ""
echo "Look for CPU% to approach ~100% (single core usage)"
echo "=================================================="
echo ""

docker stats redis-server --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}"
