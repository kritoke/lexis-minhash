## 1. Jaccard Similarity Implementation

- [x] 1.1 Add `Similarity.jaccard(set1 : Set(T), set2 : Set(T))` generic method to similarity.cr
- [x] 1.2 Add private helper `Engine.extract_shingle_set(text : String) : Set(UInt64)` using ShingleRoller
- [x] 1.3 Add `Engine.jaccard_similarity(text1 : String, text2 : String) : Float64` using shingle sets
- [x] 1.4 Add overload `Engine.jaccard_similarity(doc1 : Document, doc2 : Document) : Float64`
- [x] 1.5 Add tests for Jaccard similarity edge cases (empty, identical, partial overlap)
- [x] 1.6 Add tests for Document interface support

## 2. DRY Refactoring - Overlap Coefficient

- [x] 2.1 Update `Engine.overlap_coefficient(UInt64, UInt64)` to delegate to `Similarity.fast_overlap`
- [x] 2.2 Update `Engine.overlap_coefficient(UInt32, UInt32)` to delegate to `Similarity.fast_overlap`
- [x] 2.3 Verify all existing overlap tests still pass
- [x] 2.4 Add deprecation notice in documentation for `Engine.overlap_coefficient`

## 3. DRY Refactoring - Weight Handling

- [x] 3.1 Extract `private def self.normalize_weight(weight : Float64) : Float64?` helper in engine.cr
- [x] 3.2 Refactor `update_signature_weighted` to use normalize_weight helper
- [x] 3.3 Refactor `compute_signature_from_hashes(hashes, weights)` to use normalize_weight helper
- [x] 3.4 Verify weighted signature tests still pass

## 4. DRY Refactoring - Configuration Access

- [x] 4.1 Replace all `config` tuple unpacking with `default_config` struct access in engine.cr
- [x] 4.2 Update `generate_bands` methods to use `default_config`
- [x] 4.3 Update `compute_signature_slice_weighted_hashed` to use `default_config`
- [x] 4.4 Add documentation note that `config` tuple method is deprecated (keep for compatibility)

## 5. DRY Refactoring - Edge Case Validation

- [x] 5.1 Extract `private def self.validate_text_for_signature(text : String) : {String, Int32}?` helper
- [x] 5.2 Refactor `compute_signature_slice` to use validation helper
- [x] 5.3 Refactor `compute_signature_slice_weighted` to use validation helper
- [x] 5.4 Refactor `compute_signature_slice_weighted_hashed` to use validation helper
- [x] 5.5 Verify all signature computation tests still pass

## 6. Documentation and Finalization

- [x] 6.1 Update README.md with Jaccard similarity examples
- [x] 6.2 Update API.md with Jaccard similarity usage patterns
- [x] 6.3 Add inline documentation for new public methods
- [x] 6.4 Run full test suite and verify all tests pass
- [x] 6.5 Run linter (ameba) and fix any issues
