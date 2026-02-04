# document-comparison-helper Specification

## Purpose
TBD - created by archiving change algorithm-improvements. Update Purpose after archive.
## Requirements
### Requirement: Direct Document Comparison
The system SHALL provide a convenience method to compare two documents directly.

#### Scenario: Compare two documents
- **WHEN** Engine.compare(doc1, doc2) is called
- **THEN** the system SHALL compute signatures for both documents
- **AND** the system SHALL return their similarity score

#### Scenario: Same document comparison
- **WHEN** Engine.compare(doc, doc) is called
- **THEN** the result SHALL be 1.0

