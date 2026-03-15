# Release 0.5.0

## Breaking Changes

- **Default weight changed**: Unknown shingles in weighted signatures now use default weight `1.0` instead of `0.0`. This may produce different signatures for existing code using weighted MinHash.
- **Configuration validation**: `Engine.configure` now validates that `signature_size % num_bands == 0` and raises `ArgumentError` for invalid combinations.

## New Features

### Splitmix64 Hash Mixing
- New splitmix64-style hash combination for LSH bands provides better avalanche properties and distribution than simple XOR
- Enabled by default; existing code benefits automatically

### Functional Configuration API
- `Engine.generate_config(signature_size:, num_bands:, shingle_size:, seed:)` creates deterministic, thread-safe configurations
- Pass config explicitly to `compute_signature_with_config(cfg, text)` for pure functional usage
- Ideal for multi-threaded applications and testing

```crystal
cfg = LexisMinhash::Engine.generate_config(signature_size: 50, seed: 12345)
sig = LexisMinhash::Engine.compute_signature_with_config(cfg, "Your text")
```

### Exact Jaccard Similarity
- `Engine.jaccard_similarity(text1, text2)` computes exact Jaccard similarity based on character n-gram sets
- Useful for validating MinHash estimates or when exact values are needed

### Fast Overlap Coefficient
- `Similarity.fast_overlap(a, b)` uses optimized two-pointer algorithm (~10x faster than Set intersection)
- Works with sorted `Slice(UInt64)` or `Slice(UInt32)`

### Weighted Overlap Coefficient
- `Similarity.weighted_overlap(a, b)` computes weighted overlap for TF-IDF or other weighted document representations

### Hash-Based Signature API
- `Engine.compute_signature_from_hashes(hashes : Iterable(UInt64))` computes signatures from pre-hashed values
- `Engine.compute_signature_from_hashes(hashes, weights)` for weighted variant
- Allows callers to control hashing (xxHash, FNV, custom) while using the library's MinHash logic

### Optional Signature Storage
- `LSHIndex.new(bands:, expected_docs:, store_signatures: false)` disables signature storage to reduce memory
- Use when you only need candidate retrieval without similarity scoring

## Performance Improvements

- **26x faster** with **84% less memory allocation** compared to v0.3.x
- Rolling hash optimization with circular buffer
- Pre-hashed weights API avoids per-shingle string allocations
- Slice-based APIs for zero-copy operations

## Bug Fixes

- Memory safety fix in seeded configure (critical)
- LSHIndex band mismatch when bands differ from Engine config

## Migration Guide

### Upgrading from v0.4.x

1. If using weighted MinHash, verify default weight behavior is acceptable (now defaults to 1.0)
2. If using custom `signature_size`/`num_bands` combinations, ensure they are divisible

### Upgrading from v0.3.x

1. Update configuration: `signature_size % num_bands == 0` is now required
2. If using weights, test that unknown shingle behavior (now uses 1.0) is acceptable
3. Consider using `Engine::Config` for thread-safe applications

---

# Release 0.4.2

## Bug Fixes

- **Memory safety in seeded configure (Critical)**: Fixed memory safety bug in `Engine.configure` when using the `seed` parameter. Previously, the code was creating Slices pointing to local array memory, which would become dangling pointers after the method returned. Now uses `Pointer.malloc` to allocate properly owned memory.

- **Removed unused instance variable**: Removed unused `@rows` instance variable from `LSHIndex`.

## Improvements

- CI: Removed docs workflow (no longer using GitHub Pages)
- CI: Fixed ameba invocation to use `crystal run` instead of platform-specific binary
- CI: Removed coverage flag that was causing failures on some Crystal versions
- Documentation: Improved method documentation for `query_with_weights_by_signature`

---

# Release 0.4.1

## Bug Fixes

- **LSHIndex band mismatch (Critical)**: Fixed `IndexError` when creating `LSHIndex.new(bands: N)` where N differs from Engine's configured `num_bands`. The `generate_bands` method now accepts an optional `bands` parameter so LSHIndex can use its own band count.

- **Negative weights behavior**: Clarified test expectations - negative weights now correctly exclude terms (clamped to 0) rather than using default weight.

## Improvements

- CI: Added crystal-lang/install-crystal@v1 action for more reliable Crystal installation
- CI: Added Docker-based test job using `84codes/crystal:1.18.2-ubuntu-22.04` for reproducibility
- CI: Added shard caching to speed up CI runs
- CI: Added Codecov coverage upload and 80% threshold enforcement
- Docs: Added libxml2 installation to docs workflow for sanitized HTML output

## Tests

- Added `spec/lexis_minhash_extra_spec.cr` - ShingleRoller, signature serialization, prehash path tests
- Added `spec/lexis_minhash_more_spec.cr` - Seeded determinism, negative weights, LSHIndex edge cases

---

# Release 0.4.0

Short summary

- Added: `Engine.prehash_weights`, `Engine.compute_signature(..., hashed_weights)`, `Engine.compute_signature_with_prehashed_weights` (avoid per-shingle string allocations)
- Added: examples + `scripts/run_examples.sh`, `scripts/run_examples_ci.sh`
- Added: GitHub Actions CI (lint/test/examples) and optional release benchmarks
- Fixed: `Engine.configure` now validates `signature_size % num_bands == 0`
- Fixed: `Signature.from_blob` validates blob length and copies bytes safely
- Improved: reduced duplication and optimized weighted path
- Tests: Added validation tests for configure and from_blob

For full details see CHANGELOG and commit history.
