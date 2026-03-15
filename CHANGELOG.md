# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

# [0.5.0] - Unreleased

## Added

- **Splitmix64 Hash Mixing**: Implemented splitmix64-style hash combination for better avalanche properties and distribution in LSH band hashing
- **Engine::Config**: Functional configuration API for thread-safe, deterministic signatures without global state
- **Exact Jaccard Similarity**: `Engine.jaccard_similarity(text1, text2)` for accurate Jaccard computation based on shingle sets
- **Fast Overlap Coefficient**: `Similarity.fast_overlap(a, b)` - optimized two-pointer algorithm (~10x faster than Set intersection)
- **Weighted Overlap Coefficient**: `Similarity.weighted_overlap(a, b)` for comparing weighted document representations like TF-IDF vectors
- **Shingles Helper Methods**: `Engine.shingles_hashes` and `Engine.shingles_with_strings` for extracting shingle sets from text
- **Hash-Based Signature API**: `Engine.compute_signature_from_hashes` and weighted variant for computing signatures from pre-hashed UInt64 values

## Improved

- **Performance**: 26x faster with 84% less memory allocation through optimized rolling hash and weighted path improvements
- **Code Organization**: Split monolithic engine.cr into focused modules (config, rolling, signature, serialize)
- **Test Coverage**: Comprehensive tests for new APIs and edge cases
- **Documentation**: Added Engine::Config section to README, improved API documentation throughout

## Changed

- **Default Weight**: Changed from `0.0_f64` to `1.0_f64` for unknown shingles in weighted signatures
- **LSHIndex Storage**: Added `store_signatures` option to disable signature storage for reduced memory usage
- **Error Handling**: Better error messages for configuration validation

## Fixed

- Memory safety in seeded configure (critical fix in 0.4.2)
- LSHIndex band mismatch when bands differ from Engine config
- Removed unused instance variables

---

# [0.4.2] - 2024-02-03

## Fixed

- **Memory safety in seeded configure (Critical)**: Fixed memory safety bug in `Engine.configure` when using the `seed` parameter. Previously, the code was creating Slices pointing to local array memory, which would become dangling pointers after the method returned.
- Removed unused `@rows` instance variable from `LSHIndex`

## Improved

- CI: Removed docs workflow, fixed ameba invocation, removed coverage flag

---

# [0.4.1] - 2024-01-15

## Fixed

- **LSHIndex band mismatch (Critical)**: Fixed IndexError when creating `LSHIndex.new(bands: N)` where N differs from Engine's configured `num_bands`
- Negative weights behavior clarified

## Added

- Docker-based test job for reproducibility
- Codecov coverage upload with 80% threshold

---

# [0.4.0] - 2024-01-01

## Added

- `Engine.prehash_weights` and hashed-weight signature APIs for performance
- Examples and CI workflows

## Fixed

- Configuration validation for signature_size % num_bands
- Signature.from_blob validation

## Improved

- Reduced duplication and optimized weighted path
