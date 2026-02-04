## Context

The current MinHash implementation uses CRC32 incorrectly and relies on a "seeded hash functions" approach that lacks true MinHash theoretical guarantees. The library also lacks several practical features for similarity detection workflows.

## Goals / Non-Goals

**Goals:**
- Replace CRC32 with SHA256 for better hash distribution
- Implement true MinHash using random permutation simulation
- Add Jaccard similarity for validation
- Add configurable Engine parameters
- Add convenience methods and LSH index

**Non-Goals:**
- Breaking existing public API structure (maintain backward compatibility)
- Distributed indexing or horizontal scaling
- Persistent storage beyond signature serialization
- Real-time streaming updates

## Decisions

### 1. True MinHash Implementation

**Decision:** Use random linear hash functions (h(x) = (a*x + b) mod p) instead of seeded hash functions.

**Rationale:** True MinHash requires random permutations. The linear hash approach with randomly generated coefficients (a, b) simulates this efficiently:
- O(1) computation per shingle per hash function
- Theoretical guarantees match original MinHash paper
- Avoids expensive actual permutations

**Alternatives considered:**
- Actual permutations: O(n log n) per hash function, impractical
- Multiple SHA256 calls with incrementing salts: works but slower

### 2. Hash Function: SHA256 for Shingle Hashing

**Decision:** Hash shingles to UInt64 via SHA256, then apply linear hash functions.

**Rationale:**
- SHA256 provides uniform distribution
- Crystal's standard library includes it (no new dependencies)
- First 8 bytes converted to UInt64 for linear hash input

### 3. Configurable Engine via Class Variables

**Decision:** Use `@@config` and `@@hash_coeffs` class variables with `self.configure`.

**Rationale:**
- Maintains module-style API
- Allows runtime configuration
- Simple migration path (defaults match old behavior)

**Alternatives considered:**
- Require `Engine.new(config)` constructor: breaks existing code
- Global config object: more complex

### 4. LSH Index Class

**Decision:** Create `LSHIndex` class separate from `Engine` module.

**Rationale:**
- Follows single responsibility principle
- Stateful class appropriate for index management
- Keeps Engine as pure functions

## Risks / Trade-offs

- **[Risk]** Class variables are mutable and not thread-safe
  → **Mitigation:** Document thread-safety requirements; typical use is single-threaded

- **[Risk]** Random coefficient generation means non-deterministic signatures across runs
  → **Mitigation:** Store @@hash_coeffs after generation; consider seed parameter for reproducibility

- **[Trade-off]** Jaccard similarity computes full shingle sets (memory intensive)
  → **Mitigation:** Jaccard is for validation/calibration, not production use

## Open Questions

- Should we add a seed parameter to `configure` for reproducible signatures?
- Should LSHIndex support persistence?
