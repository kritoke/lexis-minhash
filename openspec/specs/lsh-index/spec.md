# lsh-index Specification

## Purpose
TBD - created by archiving change algorithm-improvements. Update Purpose after archive.
## Requirements
### Requirement: Add Document to Index
The system SHALL allow adding documents to an LSH index.

#### Scenario: Add single document
- **WHEN** LSHIndex.new.add("doc1", document) is called
- **THEN** the document's signature SHALL be stored
- **AND** its bands SHALL be placed in corresponding buckets

### Requirement: Query Candidates
The system SHALL return candidate documents that share bands with the query document.

#### Scenario: Find candidates
- **WHEN** index.query(document) is called
- **THEN** the system SHALL return all document IDs sharing at least one band
- **AND** the result SHALL be limited to max_candidates if specified

### Requirement: Query with Scores
The system SHALL return candidates with their similarity scores.

#### Scenario: Get scored candidates
- **WHEN** index.query_with_scores(document) is called
- **THEN** each returned document SHALL include its similarity score
- **AND** results SHALL be sorted by score descending

### Requirement: Find Similar Pairs
The system SHALL find all document pairs above a similarity threshold.

#### Scenario: Find pairs above threshold
- **WHEN** index.find_similar_pairs(0.75) is called
- **THEN** the system SHALL return all pairs with similarity >= 0.75
- **AND** each pair SHALL contain exactly two document IDs

### Requirement: Index Management
The system SHALL support basic index management operations.

#### Scenario: Get index size
- **WHEN** index.size is called
- **THEN** the system SHALL return the number of documents indexed

#### Scenario: Clear index
- **WHEN** index.clear is called
- **THEN** all documents SHALL be removed from the index

