## ADDED Requirements

### Requirement: Configurable Signature Size
The system SHALL allow configuration of the MinHash signature size.

#### Scenario: Default signature size
- **WHEN** Engine.configure is not called
- **THEN** the default signature size SHALL be 100

#### Scenario: Custom signature size
- **WHEN** Engine.configure(signature_size: 200) is called
- **THEN** all subsequent signatures SHALL have size 200

### Requirement: Configurable Band Count
The system SHALL allow configuration of the number of LSH bands.

#### Scenario: Custom band count
- **WHEN** Engine.configure(num_bands: 10) is called
- **THEN** generate_bands SHALL return 10 bands

### Requirement: Configurable Shingle Size
The system SHALL allow configuration of the shingle size for text decomposition.

#### Scenario: Custom shingle size
- **WHEN** Engine.configure(shingle_size: 4) is called
- **THEN** text SHALL be decomposed into 4-character n-grams

### Requirement: Configurable Stop Words
The system SHALL allow custom stop words for filtering.

#### Scenario: Custom stop words
- **WHEN** Engine.configure(stop_words: Set{"foo", "bar"}) is called
- **THEN** "foo" and "bar" SHALL be filtered from documents

### Requirement: Configuration Reset
The system SHALL allow resetting configuration to defaults.

#### Scenario: Reset to defaults
- **WHEN** Engine.reset_config is called
- **THEN** all configuration SHALL revert to default values
