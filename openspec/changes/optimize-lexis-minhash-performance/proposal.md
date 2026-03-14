## Why

The lexis-minhash library has several performance bottlenecks that limit its scalability in high-throughput scenarios. While the current implementation is well-architected with O(n) shingling and zero-allocation paths, there remain opportunities to reduce memory allocation, improve hash quality, and optimize data structures for better cache locality and CPU efficiency.

## What Changes

- Replace `Deque(UInt8)` in `ShingleRoller` with fixed-size circular buffer to eliminate allocation overhead
- Optimize weighted signature computation to avoid redundant String allocations by promoting hashed-weight API as primary path
- Improve band hash combination algorithm for better distribution properties using robust hash mixing
- Add optional signature storage configuration to `LSHIndex` to reduce memory usage when only candidate retrieval is needed
- Upgrade deterministic coefficient generation from simple LCG to splitmix64 for better hash distribution quality
- **BREAKING**: Deprecate string-weight APIs in favor of pre-hashed weight APIs for performance-critical use cases

## Capabilities

### New Capabilities
- `circular-buffer-shingling`: Implements fixed-size circular buffer for shingle rolling to eliminate Deque allocation overhead
- `hashed-weight-optimization`: Provides optimized weighted signature computation using pre-hashed UInt64 keys instead of String keys
- `robust-band-hashing`: Implements improved hash combination algorithm for LSH band generation with better distribution properties
- `optional-signature-storage`: Adds configuration option to LSHIndex to disable signature storage for memory-constrained scenarios
- `splitmix64-coefficients`: Upgrades deterministic coefficient generation to splitmix64 algorithm for superior hash distribution

### Modified Capabilities
- `rolling-hash`: Modifies shingle rolling implementation to use circular buffer instead of Deque
- `weighted-signatures`: Changes primary API path to favor hashed weights over string weights
- `lsh-index`: Adds optional signature storage configuration parameter

## Impact

- Core engine files: `src/lexis-minhash/engine/rolling.cr`, `src/lexis-minhash/engine.cr`
- LSH index: `src/lexis-minhash/index.cr`
- Configuration: `src/lexis-minhash/engine/config.cr`
- Performance-critical code paths affecting all signature computation APIs
- Memory allocation patterns in high-throughput scenarios
- Hash distribution quality affecting MinHash accuracy
- API surface with deprecation of string-weight methods