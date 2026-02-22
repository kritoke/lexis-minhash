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
