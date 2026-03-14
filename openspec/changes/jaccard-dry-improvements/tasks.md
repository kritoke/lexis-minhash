## 1. Jaccard Similarity Implementation

- [ ] 1.1 Add `Similarity.jaccard(set1 : Set(T), set2 : Set(T))` generic method to similarity.cr
- [ ] 1.2 Add private helper `Engine.extract_shingle_set(text : String) : Set(UInt64)` using ShingleRoller
- [ ] 1.3 Add `Engine.jaccard_similarity(text1 : String, text2 : String) : Float64` using shingle sets
- [ ] 1.4 Add overload `Engine.jaccard_similarity(doc1 : Document, doc2 : Document) : Float64`
- [ ] 1.5 Add tests for Jaccard similarity edge cases (empty, identical, partial overlap)
- [ ] 1.6 Add tests for Document interface support

## 2. DRY Refactoring - Overlap Coefficient

- [ ] 2.1 Update `Engine.overlap_coefficient(UInt64, UInt64)` to delegate to `Similarity.fast_overlap`
- [ ] 2.2 Update `Engine.overlap_coefficient(UInt32, UInt32)` to delegate to `Similarity.fast_overlap`
- [ ] 2.3 Verify all existing overlap tests still pass
- [ ] 2.4 Add deprecation notice in documentation for `Engine.overlap_coefficient`

## 3. DRY Refactoring - Weight Handling

- [ ] 3.1 Extract `private def self.normalize_weight(weight : Float64) : Float64?` helper in engine.cr
- [ ] 3.2 Refactor `update_signature_weighted` to use normalize_weight helper
- [ ] 3.3 Refactor `compute_signature_from_hashes(hashes, weights)` to use normalize_weight helper
- [ ] 3.4 Verify weighted signature tests still pass

## 4. DRY Refactoring - Configuration Access

- [ ] 4.1 Replace all `config` tuple unpacking with `default_config` struct access in engine.cr
- [ ] 4.2 Update `generate_bands` methods to use `default_config`
- [ ] 4.3 Update `compute_signature_slice_weighted_hashed` to use `default_config`
- [ ] 4.4 Add documentation note that `config` tuple method is deprecated (keep for compatibility)

## 5. DRY Refactoring - Edge Case Validation

- [ ] 5.1 Extract `private def self.validate_text_for_signature(text : String) : {String, Int32}?` helper
- [ ] 5.2 Refactor `compute_signature_slice` to use validation helper
- [ ] 5.3 Refactor `compute_signature_slice_weighted` to use validation helper
- [ ] 5.4 Refactor `compute_signature_slice_weighted_hashed` to use validation helper
- [ ] 5.5 Verify all signature computation tests still pass

## 6. Documentation and Finalization

- [ ] 6.1 Update README.md with Jaccard similarity examples
- [ ] 6.2 Update API.md with Jaccard similarity usage patterns
- [ ] 6.3 Add inline documentation for new public methods
- [ ] 6.4 Run full test suite and verify all tests pass
- [ ] 6.5 Run linter (ameba) and fix any issues
