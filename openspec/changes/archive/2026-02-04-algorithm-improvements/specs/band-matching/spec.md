## ADDED Requirements

### Requirement: Count Shared Bands
The system SHALL return the number of matching bands between two signatures.

#### Scenario: No shared bands
- **WHEN** Engine.shared_bands(sig1, sig2) is called with disjoint signatures
- **THEN** the result SHALL be 0

#### Scenario: All bands shared
- **WHEN** Engine.shared_bands(sig, sig) is called
- **THEN** the result SHALL equal the configured NUM_BANDS

#### Scenario: Partial band overlap
- **WHEN** Engine.shared_bands(sig1, sig2) is called with partially similar signatures
- **THEN** the result SHALL be an integer between 0 and NUM_BANDS

#### Scenario: Empty signatures
- **WHEN** either signature is empty
- **THEN** the result SHALL be 0
