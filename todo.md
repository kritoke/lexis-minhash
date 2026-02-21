# Lexis MinHash - v0.3.0 Release Notes

## New Features (v0.3.0)

### Seed Parameter for Reproducible Hashes
- Add `seed` parameter to `Engine.configure` for deterministic hashing
- Ensures signatures are consistent across application restarts
- Use for testing, caching, database storage

### Signature Struct
- New `LexisMinhash::Signature` struct for convenient API
- `Signature.compute(text)` - create signature from text
- `sig.to_blob` - pointer-casting serialization to Bytes (SQLite BLOB)
- `Signature.from_blob(bytes)` - deserialize from stored bytes
- `sig.similarity(other)` - direct similarity calculation

### fast_overlap Method
- Two-pointer algorithm for sorted Slices
- ~10x faster than standard Set intersection
- `Similarity.fast_overlap(a : Slice(UInt64), b : Slice(UInt64))`
- `Similarity.fast_overlap(a : Slice(UInt32), b : Slice(UInt32))`

### Decoupled UInt64 Hashing
- `Engine.compute_signature_from_hashes(hashes)` for app-controlled hashing
- Application handles String -> UInt64 conversion (xxHash, FNV, etc.)
- Engine operates purely on UInt64 hash values

### Performance Improvements
- Simplified `to_blob` using pointer casting
- Log-transform for small weights (< 1.0) to prevent precision loss
- Configurable default weight for weighted MinHash

---

## Previous Releases

## Files

```
src/lexis-minhash.cr           - Core types + backward compat
src/lexis-minhash/engine.cr    - Engine + ShingleRoller + overlap_coefficient
src/lexis-minhash/index.cr     - LSHIndex + LinearBucketTable
src/lexis-minhash/similarity.cr - Similarity module (weighted_overlap)
spec/lexis_minhash_spec.cr     - 37 tests
benchmark/benchmark.cr         - Performance + tuning
```

## Library Features

### Engine Module
- `compute_signature(text : String) : Array(UInt32)` - MinHash signature from text
- `compute_signature(text : String, weights : Hash(String, Float64)?) : Array(UInt32)` - Weighted MinHash signature
- `compute_signature_slice(text : String) : Slice(UInt32)` - Zero-copy signature
- `compute_signature_slice(text : String, weights : Hash(String, Float64)?) : Slice(UInt32)` - Weighted slice signature
- `similarity(sig1, sig2) : Float64` - Jaccard similarity (0.0 to 1.0)
- `overlap_coefficient(a : Slice(UInt64), b : Slice(UInt64)) : Float64` - Overlap coefficient
- `generate_bands(signature) : Array({Int32, UInt64})` - LSH band hashes
- `signature_to_bytes / bytes_to_signature` - Binary serialization
- `detection_probability(similarity : Float64) : Float64` - LSH probability estimate
- `configure(...)` - Runtime configuration
- `config : {Int32, Int32, Int32, Int32, Int32}` - Current config getter

### Similarity Module
- `weighted_overlap(a : Hash(String, Float64), b : Hash(String, Float64)) : Float64` - Weighted overlap coefficient

### ShingleRoller Class
- O(n) rolling hash for character k-shingles
- `roll(byte : UInt8) : UInt64?` - Process byte, returns hash when window full
- `current_shingle : String?` - Get current window content (used for weighted MinHash)
- `reset : Nil` - Reset roller state
- `window_size : Int32` - Current window size

### LSHIndex Class
- `add(doc_id : Int32, text : String)` - Add document by text
- `add_with_signature(doc_id : Int32, signature : Array(UInt32))` - Add by precomputed signature
- `add_with_weights(doc_id : Int32, text : String, weights : Hash(String, Float64))` - Add with weighted signature
- `query(text : String) : Set(Int32)` - Find candidate doc IDs
- `query_by_signature(signature : Array(UInt32)) : Set(Int32)` - Query by signature
- `query_with_weights(text : String, weights : Hash(String, Float64)) : Set(Int32)` - Query with weighted signature
- `query_with_scores(text : String) : Array({Int32, Float64})` - Results with similarity scores
- `find_similar_pairs(threshold : Float64) : Set({Int32, Int32})` - Find all similar pairs
- `get_signature(doc_id : Int32) : Array(UInt32)?` - Retrieve stored signature
- `size : Int32` - Number of indexed documents
- `load_factors : Array(Float64)` - Per-band load factors
- `clear` - Remove all documents

### LinearBucketTable Struct
- Cache-efficient LSH storage with linear probing
- `insert(key : UInt64, doc_id : Int32)` - Add entry
- `find_candidates(key : UInt64, &)` - Yield matching doc IDs
- `size / capacity / load_factor` - Table statistics

---

## Recommendations for quickheadlines

### No Code Changes Required
The backward compatibility layer ensures quickheadlines will work with v0.2.1:

```crystal
# This still works:
document = LexisMinhash::SimpleDocument.new(title)
signature = LexisMinhash::Engine.compute_signature(document)
bands = LexisMinhash::Engine.generate_bands(signature)
band_hashes = bands.map { |band| band[1] }
```

### Optional Improvements

1. **Simplify to direct string API**
   ```crystal
   # Instead of:
   document = LexisMinhash::SimpleDocument.new(title)
   signature = LexisMinhash::Engine.compute_signature(document)
   
   # Use:
   signature = LexisMinhash::Engine.compute_signature(title)
   ```

2. **Remove ClusteringUtilities STOP_WORDS**
   The new engine doesn't use stop words (character shingles don't need them).
   ClusteringUtilities.word_count can be simplified.

3. **Consider using LSHIndex for in-memory queries**
   If FeedCache ever needs in-memory candidate lookup, LSHIndex is now optimized.

---

## Known Issues & Fixes Needed

### ~~1. generate_bands inconsistency~~ (Fixed)
`generate_bands` has two overloads with different hashing logic:
- Array version: `(combined << 7) ^ _hash`
- Slice version: `band_slice.hash.to_u64`

These produce different results for the same signature. The Slice version should be fixed to match Array.

### ~~2. overlap_coefficient type mismatch~~ (Fixed)
`overlap_coefficient` accepts `Slice(UInt64)` but MinHash signatures are `UInt32`. Consider adding:
- `overlap_coefficient(sig1 : Slice(UInt32), sig2 : Slice(UInt32))` overload
- Or document that input must be sorted UInt64 arrays

### ~~3. similarity method duplication~~ (Fixed)
`similarity` has nearly identical Array and Slice implementations. Could consolidate with generics.

### ~~4. signature_to_bytes duplication~~ (Fixed)
Same as above - Array and Slice versions are nearly identical.

---

## Potential Issues & Recommendations (v0.2.2)

### Weighted MinHash Implementation

1. **Performance Concern**: The weighted signature computation is ~4.5x slower than standard MinHash due to:
   - String key lookups in the weights hash for each shingle
   - Creating `String` objects via `current_shingle` method
   
   **Recommendation**: Consider caching or pre-computing shingle-weight mappings if performance is critical. See README for caching pattern. ✅ Documented in API.md

2. **Weight Division Approach** (✅ Implemented): Current implementation divides hash by weight:
   ```crystal
   weighted_h = (combined_h.to_f64 / weight).to_u32
   ```
   This makes high-weight (rare) words produce smaller values, making them more likely to "win" min-hash slots.
   
   **Note**: The `% Float64.new(UInt32::MAX)` operation handles potential overflow but may affect distribution.

3. **Default Weight** (✅ Configurable): Unknown shingles now use configurable default weight. Set via `Engine.configure(default_weight: value)`.

4. **Hash Key Matching** (✅ Documented): Documented in Crystal docs - keys must match lowercase character n-grams (shingles). For example, "hello world" with shingle_size=5 generates: "hello", "ello ", "llo w", etc.

5. **Negative Weights** (✅ Fixed): Negative weights are clamped to 0 (treated as excluded from signature).

6. **LSHIndex with Weights** (✅ Implemented): Added `add_with_weights` and `query_with_weights` methods. Note: Documents added with weights must be queried with weights to match (signatures are different).

### Testing Recommendations

- ~~Add integration tests for weighted MinHash with LSHIndex~~ (Added)
- ~~Test edge cases: empty weights, negative weights (should be handled), very high weights~~ (Added)
- Consider adding property-based tests for weighted_overlap coefficient

### Future Considerations

1. **Configurable Default Weight**: Add parameter to set default weight for unknown shingles (currently hardcoded to 1.0)

2. **Weighted Similarity in LSHIndex**: Currently `find_similar_pairs` uses standard Jaccard similarity. Consider adding weighted similarity option.

3. **Serialization for Weighted Signatures**: Consider adding metadata to signature bytes to indicate if weights were used.

4. **Word-based Shingling Option**: Character shingles work well, but some use cases may benefit from word-based n-grams.

---

## Future Enhancements

### Low Priority
1. Word-based shingling option
2. Batch processing with fibers
3. Config serialization (JSON/YAML)
4. Add `overlap_coefficient` overload for UInt32 slices (signature type)

### Not Planned
- ~~XXHash integration~~ (rolling hash is sufficient)
- ~~Weighted MinHash~~ (niche use case) - **Added in v0.2.2**

---

# Code Audit Findings (2026-02-21)

## Summary

- **Build**: Passes (type check OK)
- **Linter (Ameba)**: 0 failures
- **Tests**: 40 examples, 0 failures

---

## Findings

### HIGH PRIORITY

#### 1. Missing validation in `configure` for signature_size divisibility
**File**: `src/lexis-minhash/engine.cr:145`

```crystal
@@rows = signature_size // num_bands
```

**Issue**: If `signature_size` is not evenly divisible by `num_bands`, the LSH banding will not work correctly. The default values (100/20=5) work, but custom configurations may break silently.

**Fix**: Add validation in `configure`:
```crystal
raise "signature_size must be divisible by num_bands" if signature_size % num_bands != 0
```

**Verify**: `crystal build src/lexis-minhash.cr` after fix

---

#### 2. Potential partial read in `Signature.from_blob`
**File**: `src/lexis-minhash/engine.cr:68-75`

```crystal
def self.from_blob(blob : Bytes) : Signature
  return Signature.new(Slice(UInt32).new(0)) if blob.empty?
  count = blob.size // sizeof(UInt32)
  slice = Slice(UInt32).new(count)
  blob.copy_to(slice.to_unsafe, blob.size)
  Signature.new(slice)
end
```

**Issue**: If `blob.size` is not a multiple of 4, the division truncates and extra bytes are silently ignored. This could hide data corruption.

**Fix**: Validate blob size:
```crystal
return Signature.new(Slice(UInt32).new(0)) if blob.empty?
raise "Invalid blob size" if blob.size % sizeof(UInt32) != 0
```

**Verify**: Add test with malformed blob

---

### MEDIUM PRIORITY

#### 3. Duplicate code between compute_signature methods
**Files**: `src/lexis-minhash/engine.cr:182-208` and `211-237`

**Issue**: `compute_signature` and `compute_signature_slice` share almost identical logic. Same with weighted versions. This violates DRY and makes maintenance harder.

**Fix**: Refactor to have one implementation that returns the desired type, or use a macro/generic.

**Verify**: `crystal spec` should still pass

---

#### 4. Duplicate `fast_overlap` implementations
**File**: `src/lexis-minhash/similarity.cr:46-62` and `67-83`

**Issue**: Nearly identical code for `Slice(UInt64)` and `Slice(UInt32)`. Could use generics.

**Fix**: Use a generic method or single implementation.

---

#### 5. Unused instance variable in LSHIndex
**File**: `src/lexis-minhash/index.cr:80,90`

```crystal
@rows : Int32
# ...
@rows = 5  # Never read
```

**Issue**: Dead code - `@rows` is declared and assigned but never used.

**Fix**: Remove the unused `@rows` instance variable.

**Verify**: `bin/ameba` (should still pass)

---

### LOW PRIORITY

#### 6. Manual byte serialization could be simplified
**Files**: `src/lexis-minhash/engine.cr:513-551`

**Issue**: `signature_to_bytes`, `bytes_to_signature`, `bytes_to_signature_slice` use manual byte manipulation. Crystal's `Slice#reinterpret` or `Bytes.new` with block could simplify.

**Fix**: Consider using Crystal's built-in serialization helpers.

---

#### 7. Missing return type on some private methods
**File**: `src/lexis-minhash/engine.cr:239`

```crystal
private def self.update_signature(signature : Slice(UInt32), h64 : UInt64)
```

**Issue**: While Crystal infers `Nil`, explicit return type follows project conventions.

**Fix**: Add `: Nil` return type.

---

## Security Assessment

**Good**:
- No `system`, `exec`, or shell injection vectors
- No `eval` or unsafe deserialization (`Marshal.load`)
- Uses `Random::Secure` for cryptographic randomness
- `to_unsafe` only used for legitimate serialization (reinterpreting memory)

**Note**: The serialization code (`to_blob`/`from_blob`) uses `to_unsafe` for efficient byte-level operations. This is a common and acceptable pattern in Crystal when dealing with binary formats like SQLite BLOBs.

---

## Recommendations

1. **Fix immediately**: Items 1-2 (validation issues)
2. **Fix soon**: Items 3-5 (code quality)
3. **Consider**: Item 6-7 (refinement)
