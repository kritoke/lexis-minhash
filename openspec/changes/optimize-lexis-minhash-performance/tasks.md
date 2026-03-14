## 1. Circular Buffer Shingling Implementation

- [x] 1.1 Replace Deque(UInt8) with StaticArray(UInt8, 32) in ShingleRoller
- [x] 1.2 Implement circular buffer logic for roll() method
- [x] 1.3 Add MAX_SHINGLE_SIZE constant and validation in Engine.configure
- [x] 1.4 Update shingles_hashes helper to use circular buffer approach
- [x] 1.5 Add tests for circular buffer edge cases and size validation

## 2. Hashed Weight Optimization

- [x] 2.1 Refactor compute_signature_slice_weighted to delegate to hashed version
- [x] 2.2 Implement prehash_weights optimization in string-weight path
- [x] 2.3 Update documentation to recommend hashed-weight APIs
- [x] 2.4 Add deprecation warnings to string-weight APIs
- [x] 2.5 Create comprehensive tests verifying equivalence between APIs

## 3. Robust Band Hashing Implementation

- [x] 3.1 Implement splitmix64-style hash combination function
- [x] 3.2 Replace band hash combination logic in generate_bands methods
- [x] 3.3 Add optional legacy algorithm configuration parameter
- [x] 3.4 Update tests to verify deterministic output and distribution quality
- [x] 3.5 Add benchmark comparison between old and new algorithms

## 4. Optional Signature Storage

- [x] 4.1 Add store_signatures parameter to LSHIndex.initialize constructor
- [x] 4.2 Modify add() methods to conditionally store signatures
- [x] 4.3 Update query_with_scores to raise NotImplementedError when storage disabled
- [x] 4.4 Add tests for both enabled and disabled storage scenarios
- [x] 4.5 Update documentation and examples for optional storage feature

## 5. Splitmix64 Coefficient Generation

- [ ] 5.1 Implement splitmix64 algorithm for coefficient generation
- [ ] 5.2 Replace LCG implementation in generate_config with splitmix64
- [ ] 5.3 Ensure a_slice coefficients remain odd numbers for mathematical correctness
- [ ] 5.4 Add comprehensive tests for deterministic behavior and quality improvement
- [ ] 5.5 Update documentation about improved randomness quality

## 6. Integration and Validation

- [ ] 6.1 Run all existing tests to ensure backward compatibility
- [ ] 6.2 Run performance benchmarks to measure improvements
- [ ] 6.3 Update AGENTS.md with new build/test commands if needed
- [ ] 6.4 Run ameba linter and fix any issues
- [ ] 6.5 Create final integration test covering all optimizations together
