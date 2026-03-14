## ADDED Requirements

### Requirement: Optional signature storage in LSHIndex
The LSHIndex class SHALL support optional signature storage through a store_signatures constructor parameter that defaults to true.

#### Scenario: Default signature storage enabled
- **WHEN** LSHIndex is initialized without explicit store_signatures parameter
- **THEN** it stores signatures internally and query_with_scores functionality works normally

#### Scenario: Signature storage disabled
- **WHEN** LSHIndex is initialized with store_signatures: false
- **THEN** it does not store signatures internally
- **AND** add() methods still function normally for candidate retrieval
- **AND** query() methods return candidates but query_with_scores raises NotImplementedError

#### Scenario: Memory usage reduction
- **WHEN** store_signatures is disabled
- **THEN** memory usage is reduced by approximately 50% compared to enabled state for the same dataset

### Requirement: Query functionality with disabled storage
The LSHIndex SHALL maintain basic candidate retrieval functionality even when signature storage is disabled.

#### Scenario: Basic query with disabled storage
- **WHEN** store_signatures is false and query() is called
- **THEN** it returns candidate document IDs from band tables
- **AND** does not attempt signature similarity computation

#### Scenario: Scored query with disabled storage
- **WHEN** store_signatures is false and query_with_scores() is called
- **THEN** it raises NotImplementedError with descriptive message about disabled signature storage