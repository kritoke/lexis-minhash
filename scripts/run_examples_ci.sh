#!/usr/bin/env bash
set -euo pipefail

# Run examples in CI without --release to keep runtime predictable in CI environments
for f in examples/*.cr; do
  echo "Running example: $f"
  crystal run "$f"
done

echo "All examples finished (CI)"
