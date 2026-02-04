## 1. Hash Function Update

- [ ] 1.1 Replace Digest::CRC32 import with Digest::SHA256
- [ ] 1.2 Implement sha256_hash method to convert String to UInt64
- [ ] 1.3 Update hash_shingle to use SHA256

## 2. True MinHash Implementation

- [ ] 2.1 Define HashCoeffs record with a, b coefficients and hash method
- [ ] 2.2 Implement generate_hash_coeffs to create k random coefficient pairs
- [ ] 2.3 Replace seeded hash approach with true MinHash linear hash simulation
- [ ] 2.4 Store hash_coeffs as class variable and initialize on configure

## 3. Configurable Engine

- [ ] 3.1 Create Config struct with signature_size, num_bands, shingle_size, min_words, stop_words
- [ ] 3.2 Add Engine.configure method with default values
- [ ] 3.3 Add Engine.reset_config method
- [ ] 3.4 Update all methods to use @@config instead of hardcoded constants
- [ ] 3.5 Update generate_bands to use config.rows_per_band

## 4. Jaccard Similarity

- [ ] 4.1 Implement private shingles_to_set helper method
- [ ] 4.2 Implement Engine.jaccard_similarity(doc1, doc2) method
- [ ] 4.3 Add tests for Jaccard similarity edge cases

## 5. Document Comparison Helper

- [ ] 5.1 Implement Engine.compare(doc1, doc2) convenience method
- [ ] 5.2 Add tests for compare method

## 6. Band Matching Utility

- [ ] 6.1 Implement Engine.shared_bands(sig1, sig2) method
- [ ] 6.2 Add tests for shared_bands

## 7. LSH Index Class

- [ ] 7.1 Create LSHIndex class with @buckets and @signatures Hash structures
- [ ] 7.2 Implement add(doc_id, document) method
- [ ] 7.3 Implement query(document, max_candidates) method
- [ ] 7.4 Implement query_with_scores(document, max_candidates) method
- [ ] 7.5 Implement find_similar_pairs(threshold) method
- [ ] 7.6 Add size and clear methods
- [ ] 7.7 Add tests for LSHIndex

## 8. Testing & Validation

- [ ] 8.1 Run existing test suite to verify backward compatibility
- [ ] 8.2 Add new tests for all new methods
- [ ] 8.3 Run ameba linter
- [ ] 8.4 Update README with new features and configuration options
