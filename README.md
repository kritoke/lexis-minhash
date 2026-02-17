# Lexis MinHash

Lexis MinHash is a locality-sensitive hashing (LSH) library for detecting similar text documents using the MinHash technique. It provides efficient clustering of similar documents by generating hash signatures and using banding techniques for fast similarity search.

## Features

- **MinHash Signature Generation**: Generate unique hash signatures for text documents using true MinHash with k random hash functions
- **Jaccard Similarity Calculation**: Compute exact Jaccard similarity between documents using shingle sets
- **Signature Similarity**: Fast approximate similarity using MinHash signatures
- **Locality-Sensitive Hashing (LSH)**: Efficiently find candidate similar documents using banding
- **LSH Index**: In-memory index for fast similarity queries across document collections
- **Stop Word Filtering**: Remove common words that don't contribute to document meaning
- **Runtime Configuration**: Adjust signature size, band count, shingle size, and more at runtime

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

The engine supports runtime configuration via the `configure` method:

```crystal
LexisMinhash::Engine.configure(
  signature_size: 100,    # Number of hash functions
  num_bands: 20,          # Number of bands for LSH
  shingle_size: 3,        # Shingle size for text decomposition
  min_words: 6,           # Minimum word count for clustering
  stop_words: LexisMinhash::DEFAULT_STOP_WORDS
)
```

Default configuration values:
- `signature_size`: 100
- `num_bands`: 20
- `rows_per_band`: 5 (calculated as signature_size / num_bands)
- `shingle_size`: 3
- `min_words`: 6

Reset to defaults:
```crystal
LexisMinhash::Engine.reset_config
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

## Performance

FastEngine uses rolling hash + multiply-shift instead of SHA256:

```
Engine.compute_signature    42.14  (23.73ms)   44.10× slower
FastEngine.compute_signature 1.86k (538.12µs)       fastest
```

**FastEngine is ~44x faster** than the SHA256-based Engine.

### LSH Parameter Tuning

For 100 hashes targeting 0.75 similarity:

| Bands (b) | Rows (r) | Threshold | Prob @ Target |
|-----------|----------|-----------|---------------|
| 10        | 10       | 0.794     | 43.99%        |
| 20        | 5        | 0.549     | 99.56%        |
| 25        | 4        | 0.447     | 99.99%        |

Default (20 bands, 5 rows) gives 99.56% detection at 0.75 similarity.

Run benchmarks: `crystal run benchmark/benchmark.cr --release`

## LSH Index

The `LSHIndex` class provides an in-memory index for efficient similarity queries:

```crystal
index = LexisMinhash::LSHIndex.new

# Add documents
index.add("doc1", LexisMinhash::SimpleDocument.new("First document text"))
index.add("doc2", LexisMinhash::SimpleDocument.new("Second document text"))

# Query for similar documents
candidates = index.query(LexisMinhash::SimpleDocument.new("First document text"))

# Query with similarity scores
scored = index.query_with_scores(LexisMinhash::SimpleDocument.new("First document text"))
scored.each do |doc_id, score|
  puts "#{doc_id}: #{score}"
end

# Find all similar pairs above threshold
pairs = index.find_similar_pairs(threshold: 0.75)

# Get index size
puts index.size

# Clear the index
index.clear
```

## API Reference

### Engine Methods

| Method | Description |
|--------|-------------|
| `compute_signature(document)` | Generate MinHash signature for a document |
| `similarity(sig1, sig2)` | Compare two signatures (0.0 to 1.0) |
| `compare(doc1, doc2)` | Compare two documents directly |
| `jaccard_similarity(doc1, doc2)` | Compute exact Jaccard similarity |
| `generate_bands(signature)` | Generate LSH bands from signature |
| `shared_bands(sig1, sig2)` | Count shared bands between signatures |
| `detection_probability(similarity)` | Probability of detecting items at given similarity |
| `signature_to_bytes(signature)` | Convert signature to bytes for storage |
| `bytes_to_signature(bytes)` | Convert bytes back to signature |

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
