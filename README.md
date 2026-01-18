# Lexis MinHash

Lexis MinHash is a locality-sensitive hashing (LSH) library for detecting similar text documents using the MinHash technique. It provides efficient clustering of similar documents by generating hash signatures and using banding techniques for fast similarity search.

## Features

- **MinHash Signature Generation**: Generate unique hash signatures for text documents
- **Jaccard Similarity Calculation**: Compute similarity between document signatures
- **Locality-Sensitive Hashing (LSH)**: Efficiently find candidate similar documents using banding
- **Stop Word Filtering**: Remove common words that don't contribute to document meaning
- **Configurable Parameters**: Adjust signature size, band count, and similarity thresholds

## Installation

Add the dependency to your `shard.yml`:

```yaml
dependencies:
  lexis-minhash:
    github: kritoke/lexis-minhash
    version: ~> 0.1.0
```

Then run `shards install`.

## Usage

### Document Interface

The Lexis MinHash engine requires all documents to implement the `LexisMinhash::Document` interface, which defines a single method `text : String` that returns the text content of the document for signature calculation.

### Basic Usage

```crystal
require "lexis-minhash"

# Create document instances using the built-in SimpleDocument
document1 = LexisMinhash::SimpleDocument.new("Document 1 text here")
document2 = LexisMinhash::SimpleDocument.new("Document 2 text here")

# Generate signatures
sig1 = LexisMinhash::Engine.compute_signature(document1)
sig2 = LexisMinhash::Engine.compute_signature(document2)

# Calculate similarity
similarity = LexisMinhash::Engine.similarity(sig1, sig2)
puts "Similarity: #{similarity}"

# Find candidate similar documents using LSH
bands1 = LexisMinhash::Engine.generate_bands(sig1)
bands2 = LexisMinhash::Engine.generate_bands(sig2)

# Check if they share any bands (potential candidates)
shared_bands = bands1 & bands2
puts "Shared bands: #{shared_bands.size}"
```

### Using Custom Document Types

You can implement your own document types by including the `LexisMinhash::Document` module:

```crystal
struct MyDocument
  include LexisMinhash::Document

  getter text : String

  def initialize(@text : String)
  end
end

# Now use your custom document type
doc = MyDocument.new("Custom document text")
sig = LexisMinhash::Engine.compute_signature(doc)
```

## Configuration

The engine has several configurable constants:

```crystal
LexisMinhash::Engine::SIGNATURE_SIZE          # Number of hash functions (100)
LexisMinhash::Engine::NUM_BANDS                # Number of bands for LSH (20)
LexisMinhash::Engine::ROWS_PER_BAND            # Rows per band (5)
LexisMinhash::Engine::SIMILARITY_THRESHOLD     # Default similarity threshold (0.75)
LexisMinhash::Engine::SHORT_HEADLINE_THRESHOLD # Threshold for short texts (0.85)
LexisMinhash::Engine::MIN_WORDS_FOR_CLUSTERING # Minimum word count for clustering (6)
LexisMinhash::Engine::SHINGLE_SIZE             # Shingle size for text decomposition (3)
```

## Algorithms

### MinHash

MinHash (minimum hash) is a technique for quickly estimating the Jaccard similarity between two sets. It works by:

1. Converting text to shingles (character n-grams)
2. Applying multiple hash functions to each shingle
3. Recording the minimum hash value for each hash function
4. The signature similarity approximates Jaccard similarity

### Locality-Sensitive Hashing (LSH)

LSH allows for efficient approximate nearest neighbor search in high-dimensional spaces. The implementation uses:

1. Signature matrix banding
2. Hash-based indexing of bands
3. Fast candidate pair generation

## Development

To run the test suite:

```bash
crystal spec
```

To run the linter:

```bash
bin/ameba
```

## Contributing

1. Fork it (<https://github.com/kritoke/lexis-minhash/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## License

MIT
