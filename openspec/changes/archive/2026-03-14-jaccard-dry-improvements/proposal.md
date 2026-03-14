## Why

The library lacks true Jaccard similarity calculation, relying only on MinHash approximation. Additionally, code analysis reveals DRY violations: duplicate overlap coefficient implementations, inconsistent configuration access patterns, scattered weight handling logic, and repeated edge case validation across signature computation methods. These issues reduce maintainability and increase the risk of bugs.

## What Changes

### New Features
- Add `LexisMinhash::Engine.jaccard_similarity(doc1, doc2)` for exact Jaccard similarity based on shingle sets
- Support both String and Document interface parameters for Jaccard similarity
- Add `LexisMinhash::Similarity.jaccard(set1, set2)` as a generic Jaccard implementation

### Code Quality Improvements (No API Changes)
- Extract duplicate overlap coefficient logic into `Similarity.fast_overlap` (already exists, remove duplicates from Engine)
- Centralize configuration access through `Config` struct consistently
- Create private weight normalization helper to eliminate repeated weight clamping logic
- Consolidate signature edge case validation (empty text, minimum words) into shared private methods
- Standardize signature size constant usage across codebase

### API Consistency
- Ensure Jaccard similarity follows same parameter patterns as existing similarity methods
- Use consistent error handling (return 0.0 for edge cases, raise ArgumentError only for invalid config)
- Support both Array(UInt32) and Slice(UInt32) uniformly where applicable

## Capabilities

### New Capabilities
- `jaccard-similarity`: Calculate true Jaccard similarity between documents based on shingle sets (spec already exists, needs implementation)

### Modified Capabilities
None - this change adds new functionality and refactors internals without modifying existing spec-level requirements.

## Impact

### Affected Code
- `src/lexis-minhash/engine.cr` - Add jaccard_similarity method, remove duplicate overlap_coefficient, extract helpers
- `src/lexis-minhash/similarity.cr` - Add jaccard method, ensure overlap methods are canonical
- `spec/lexis_minhash_spec.cr` - Add tests for jaccard_similarity
- Test files may use centralized constants instead of hardcoded values

### API Additions (Non-Breaking)
- `LexisMinhash::Engine.jaccard_similarity(text1 : String, text2 : String) : Float64`
- `LexisMinhash::Engine.jaccard_similarity(doc1 : Document, doc2 : Document) : Float64`
- `LexisMinhash::Similarity.jaccard(a : Set(T), b : Set(T)) : Float64 forall T`

### Backwards Compatibility
All existing public APIs remain unchanged. This is a pure addition with internal refactoring.
