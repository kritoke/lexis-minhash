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
