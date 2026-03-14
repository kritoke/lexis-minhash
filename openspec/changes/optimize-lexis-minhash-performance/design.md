## Context

The lexis-minhash library currently uses several suboptimal data structures and algorithms that create performance bottlenecks in high-throughput scenarios. The primary issues are:

1. **Deque allocation overhead**: `ShingleRoller` uses `Deque(UInt8)` which allocates memory for each shingle operation
2. **String allocation in weighted signatures**: The weighted signature computation allocates String objects for every shingle, then immediately discards them after hash lookups
3. **Suboptimal hash combination**: Band hash generation uses simple XOR with bit shifting that may not provide optimal distribution
4. **Memory inefficiency**: `LSHIndex` stores full signatures redundantly when they're already encoded in band tables
5. **Weak coefficient generation**: Simple LCG provides inadequate randomness for hash function coefficients

## Goals / Non-Goals

**Goals:**
- Reduce memory allocations by 50-70% in weighted signature computation
- Improve shingling throughput by 10-15% through circular buffer optimization
- Enhance hash distribution quality for better MinHash accuracy
- Reduce LSHIndex memory usage by up to 50% with optional signature storage
- Maintain backward compatibility while deprecating inefficient APIs

**Non-Goals:**
- Changing the core MinHash algorithm or mathematical properties
- Breaking existing API contracts (only deprecating)
- Adding external dependencies
- Modifying the Document interface pattern

## Decisions

### 1. Circular Buffer vs Deque for ShingleRoller
**Decision**: Replace `Deque(UInt8)` with fixed-size `StaticArray(UInt8, MAX_SHINGLE_SIZE)` and manual circular buffer management.

**Rationale**: 
- Eliminates dynamic allocation overhead completely
- Provides predictable memory layout for better cache locality
- Reduces memory fragmentation in high-throughput scenarios
- Fixed maximum shingle size (currently 5) makes this feasible

**Alternatives considered**:
- Keep Deque: maintains current behavior but doesn't solve allocation overhead
- Use Array(UInt8): still requires dynamic allocation and copying

### 2. Primary Hashed-Weight API Path
**Decision**: Make `compute_signature_slice_weighted_hashed` the primary implementation and have string-weight APIs delegate to it.

**Rationale**:
- Eliminates redundant String allocation and deallocation
- Reduces GC pressure significantly in batch processing scenarios
- Maintains backward compatibility while improving performance
- Encourages best practices through API design

**Implementation approach**: 
- `compute_signature_slice_weighted` will call `prehash_weights` once, then delegate to hashed version
- This provides immediate performance benefit without breaking changes

### 3. Robust Hash Combination Algorithm
**Decision**: Replace `(combined << 7) ^ _hash` with splitmix64-style mixing: `a = (a ^ b) * 0x9e3779b97f4a7c15_u64; a = (a ^ (a >> 32))`

**Rationale**:
- Provides better avalanche properties and distribution
- Proven in production hash table implementations
- Minimal performance overhead compared to current approach
- Better collision resistance for LSH applications

### 4. Optional Signature Storage Configuration
**Decision**: Add `store_signatures : Bool = true` parameter to `LSHIndex.initialize` constructor.

**Rationale**:
- Allows memory-constrained applications to disable signature storage
- Maintains full functionality when enabled (default behavior)
- Simple boolean flag doesn't complicate API significantly
- Reduces memory usage by ~50% when disabled

### 5. Splitmix64 Coefficient Generation
**Decision**: Replace LCG with splitmix64 algorithm for deterministic coefficient generation.

**Rationale**:
- Splitmix64 provides excellent randomness quality with minimal state
- Widely used and battle-tested in hash table implementations
- Maintains deterministic behavior when seeded
- Better statistical properties than simple LCG

## Risks / Trade-offs

**[Risk] Circular buffer size limitation** → Mitigation: Set reasonable maximum shingle size (e.g., 32 bytes) and validate configuration at startup

**[Risk] Performance regression in edge cases** → Mitigation: Comprehensive benchmarking before and after each optimization

**[Risk] Increased code complexity** → Mitigation: Clear documentation and maintain separate performance-critical paths from user-facing APIs

**[Risk] Breaking changes from deprecation** → Mitigation: Maintain backward compatibility through delegation, only deprecate (don't remove) string-weight APIs initially

**[Risk] Hash distribution changes affecting existing indexes** → Mitigation: Make improved hash combination configurable with opt-in default initially