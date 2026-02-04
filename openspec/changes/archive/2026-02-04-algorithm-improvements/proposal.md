## Why

The current MinHash implementation has two fundamental issues: (1) CRC32 is being used incorrectly and is not designed for hash-based similarity estimation, and (2) the "seeded hash functions" approach lacks the theoretical guarantees of true MinHash using random permutations. Additionally, the library lacks several useful features for practical similarity detection workflows.

## What Changes

- Replace `Digest::CRC32` with `Digest::SHA256` for better hash distribution
- Implement true MinHash using random permutation simulation with min-bit technique
- Add `jaccard_similarity` method for validating MinHash estimates
- Add configurable Engine initialization for tuning signature_size, num_bands, shingle_size
- Add `Engine.compare(doc1, doc2)` convenience method
- Add `LSHIndex` class for in-memory candidate retrieval
- Add `Engine.shared_bands(sig1, sig2)` to return band match count

## Capabilities

### New Capabilities
- `jaccard-similarity`: Calculate true Jaccard similarity between documents for validation
- `configurable-engine`: Initialize Engine with custom parameters for tuning
- `document-comparison-helper`: Convenience methods for direct document comparison
- `lsh-index`: In-memory index for efficient candidate retrieval
- `band-matching`: Utility to count matching bands between signatures

### Modified Capabilities
- None (existing capability behavior unchanged)

## Impact

- **Code**: `src/lexis-minhash.cr` - replace hash_shingle, add new methods, refactor compute_signature
- **Dependencies**: None (uses existing Crystal standard library)
- **API**: Breaking changes to Engine (adds initialize method, new public methods)
- **Performance**: True MinHash may be slightly slower but more accurate
