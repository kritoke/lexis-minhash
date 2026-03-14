## ADDED Requirements

### Requirement: Primary hashed-weight API path
The compute_signature_slice_weighted method SHALL delegate to compute_signature_slice_weighted_hashed by pre-hashing weights once and reusing the hashed map.

#### Scenario: Weighted signature with string keys
- **WHEN** compute_signature_slice_weighted is called with Hash(String, Float64) weights
- **THEN** it calls prehash_weights once to convert to Hash(UInt64, Float64)
- **AND** delegates to compute_signature_slice_weighted_hashed for actual computation

#### Scenario: Performance equivalence
- **WHEN** both string-key and hashed-key APIs are called with equivalent weights
- **THEN** they produce identical signatures
- **AND** the hashed-key API has lower memory allocation

### Requirement: Prehash weights efficiency
The prehash_weights method SHALL efficiently convert Hash(String, Float64) to Hash(UInt64, Float64) using the same rolling hash algorithm as shingle generation.

#### Scenario: Prehash weights conversion
- **WHEN** prehash_weights is called with string-keyed weights
- **THEN** it uses shingle_hash_for for each key to generate UInt64 hash
- **AND** returns Hash(UInt64, Float64) with identical weight values

## MODIFIED Requirements

### Requirement: Weighted signature computation performance
The system SHALL minimize memory allocations during weighted signature computation by avoiding intermediate String allocations for shingles.

#### Scenario: Zero string allocation in hashed path
- **WHEN** compute_signature_slice_weighted_hashed processes text
- **THEN** it uses ShingleRoller.roll() directly without calling current_shingle()
- **AND** performs hash lookups using UInt64 keys only