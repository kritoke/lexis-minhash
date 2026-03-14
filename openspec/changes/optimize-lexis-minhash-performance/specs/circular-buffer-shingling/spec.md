## ADDED Requirements

### Requirement: ShingleRoller uses circular buffer
The ShingleRoller class SHALL use a fixed-size circular buffer instead of Deque(UInt8) for storing shingle bytes to eliminate dynamic allocation overhead.

#### Scenario: Circular buffer initialization
- **WHEN** ShingleRoller is initialized with window_size
- **THEN** it allocates a fixed-size StaticArray(UInt8, MAX_SHINGLE_SIZE) internally

#### Scenario: Circular buffer rolling operation
- **WHEN** bytes are rolled through ShingleRoller.roll()
- **THEN** it maintains the sliding window using circular buffer logic without allocating new memory

### Requirement: Maximum shingle size validation
The system SHALL validate that configured shingle sizes do not exceed the maximum supported size (32 bytes) and raise ArgumentError if exceeded.

#### Scenario: Valid shingle size configuration
- **WHEN** Engine.configure is called with shingle_size <= 32
- **THEN** configuration succeeds without error

#### Scenario: Invalid shingle size configuration
- **WHEN** Engine.configure is called with shingle_size > 32
- **THEN** it raises ArgumentError with descriptive message