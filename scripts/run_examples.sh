#!/usr/bin/env bash
set -euo pipefail

# Run all examples under examples/ in release mode where appropriate
for f in examples/*.cr; do
  echo "Running example: $f"
  crystal run "$f" --release
done

echo "All examples finished"
