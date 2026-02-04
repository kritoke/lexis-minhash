## ADDED Requirements

### Requirement: Jaccard Similarity Calculation
The system SHALL calculate the true Jaccard similarity between two documents based on their shingle sets.

#### Scenario: Identical documents
- **WHEN** two documents with identical content are compared
- **THEN** the Jaccard similarity SHALL return 1.0

#### Scenario: Completely different documents
- **WHEN** two documents with no common shingles are compared
- **THEN** the Jaccard similarity SHALL return 0.0

#### Scenario: Partial overlap
- **WHEN** two documents share some shingles
- **THEN** the Jaccard similarity SHALL return a value between 0.0 and 1.0 proportional to overlap

#### Scenario: Empty documents
- **WHEN** either document has no shingles
- **THEN** the Jaccard similarity SHALL return 0.0
