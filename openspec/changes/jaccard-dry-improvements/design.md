## Context

The lexis-minhash library currently provides MinHash-based similarity estimation but lacks true Jaccard similarity calculation. Code analysis identified several DRY violations affecting maintainability:

1. **Duplicate overlap coefficient**: Nearly identical implementations in `Engine.overlap_coefficient` and `Similarity.fast_overlap`
2. **Inconsistent configuration access**: Mixed usage of `default_config` struct vs `config` tuple
3. **Scattered weight handling**: Repeated weight normalization/clamping across multiple methods
4. **Repeated edge case validation**: Similar empty/size checks across signature computation variants

The existing codebase uses:
- `ShingleRoller` class for rolling hash computation
- `Config` struct for engine configuration (added in recent refactor)
- `Slice(UInt32)` for high-performance signature operations
- `Array(UInt32)` for backward-compatible APIs

## Goals / Non-Goals

**Goals:**
- Implement true Jaccard similarity using shingle sets
- Remove duplicate overlap coefficient code (delegate to Similarity module)
- Standardize on `Config` struct for all configuration access
- Extract shared helpers for weight normalization and edge case validation
- Maintain 100% backwards compatibility

**Non-Goals:**
- Changing existing similarity calculation behavior
- Modifying LSH index implementation
- Performance optimization of existing methods (refactor only)
- Adding weighted Jaccard similarity (future work)

## Decisions

### Decision 1: Jaccard Implementation Strategy

**Choice**: Generate shingle sets using existing `ShingleRoller`, then compute |A ∩ B| / |A ∪ B|

**Rationale**: 
- Reuses existing rolling hash infrastructure
- O(n) shingle generation without string allocations
- Simple set intersection/union on UInt64 hashes
- Consistent with how signatures are computed

**Alternatives Considered**:
- Extract shingles as strings → higher memory allocation
- Use signature-based approximation → defeats purpose of "true" Jaccard

### Decision 2: DRY Refactoring Approach

**Choice**: Extract private helpers within Engine module, delegate overlap to Similarity module

**Rationale**:
- Keeps refactoring internal (no public API changes)
- Similarity module already exists for similarity measures
- Private helpers maintain encapsulation

**Pattern**:
```crystal
# Private helper for weight normalization
private def self.normalize_weight(weight : Float64) : Float64?
  effective = Math.max(weight, 0.0_f64)
  return nil if effective <= 0.0_f64
  effective
end

# Private helper for text validation
private def self.validate_text(text : String) : {String, Int32}?
  normalized = text.downcase.strip
  return nil if normalized.empty?
  # ... additional checks
  {normalized, word_count}
end
```

### Decision 3: Configuration Access Standardization

**Choice**: Use `default_config` struct everywhere, deprecate `config` tuple method

**Rationale**:
- Config struct provides type-safe access
- Tuple unpacking is error-prone (position-dependent)
- Matches modern Crystal patterns

**Migration**: Keep `config` tuple method for backwards compatibility but mark as deprecated in docs

### Decision 4: Overlap Coefficient Delegation

**Choice**: Remove `Engine.overlap_coefficient`, add deprecation notice, delegate to `Similarity.fast_overlap`

**Rationale**:
- Similarity module is the canonical location for similarity measures
- Removes ~45 lines of duplicate code
- `fast_overlap` already handles both UInt32 and UInt64 slices

**Implementation**:
```crystal
# In engine.cr
def self.overlap_coefficient(a : Slice(UInt64), b : Slice(UInt64)) : Float64
  Similarity.fast_overlap(a, b)
end

def self.overlap_coefficient(a : Slice(UInt32), b : Slice(UInt32)) : Float64
  Similarity.fast_overlap(a, b)
end
```

## Risks / Trade-offs

### Risk 1: Performance Impact from Set Allocation
**Risk**: Jaccard similarity requires building full shingle sets, which is O(n) memory
**Mitigation**: 
- Document memory characteristics in API docs
- Use Set(UInt64) instead of Set(String) to minimize allocations
- Reuse existing rolling hash infrastructure

### Risk 2: Breaking Change from Removing Overlap
**Risk**: Users may depend on `Engine.overlap_coefficient`
**Mitigation**: 
- Keep method signatures identical (delegation pattern)
- Mark as deprecated in documentation only (no runtime warning to avoid noise)
- Maintain for at least 2 major versions

### Risk 3: Test Coverage Gaps
**Risk**: Refactoring may introduce subtle bugs in edge cases
**Mitigation**: 
- Add comprehensive tests for all new helpers
- Run full test suite after each refactoring step
- Test both String and Document interface paths

## Migration Plan

Not applicable - this is a non-breaking addition with internal refactoring. Users simply gain new APIs:

1. `Engine.jaccard_similarity(text1, text2)` - new method
2. `Similarity.jaccard(set1, set2)` - new method
3. Existing methods continue to work identically

## Open Questions

None - design is straightforward with clear implementation path.
