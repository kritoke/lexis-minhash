# Lexis MinHash

Lexis MinHash is a locality-sensitive hashing (LSH) library for detecting similar text documents using the MinHash technique. It uses rolling hash + multiply-shift for O(n) performance.

## Features

- **O(n) MinHash Signatures**: Rolling hash + multiply-shift, no intermediate string allocations
- **Signature Similarity**: Fast approximate Jaccard similarity estimation
- **Locality-Sensitive Hashing (LSH)**: Efficient candidate retrieval using banding
- **LSH Index**: In-memory index with linear probing for cache-efficient storage
- **Thread-Safe**: Mutex-protected configuration
- **Runtime Configuration**: Adjust signature size, band count, shingle size at runtime

## Installation

Add the dependency to your `shard.yml`:

```yaml
dependencies:
  lexis-minhash:
    github: kritoke/lexis-minhash
    version: ~> 0.2.0
```

Then run `shards install`.

## Usage

### Basic Usage

```crystal
require "lexis-minhash"

# Generate signatures directly from strings
sig1 = LexisMinhash::Engine.compute_signature("Document 1 text here")
sig2 = LexisMinhash::Engine.compute_signature("Document 2 text here")

# Calculate similarity (0.0 to 1.0)
similarity = LexisMinhash::Engine.similarity(sig1, sig2)
puts "Similarity: #{similarity}"

# Generate LSH bands for candidate detection
bands = LexisMinhash::Engine.generate_bands(sig1)
# bands is Array({Int32, UInt64}) with {band_index, band_hash} tuples
```

### Using LSHIndex

```crystal
# Create index with expected document count for capacity planning
index = LexisMinhash::LSHIndex.new(bands: 20, expected_docs: 1000)

# Add documents with Int32 IDs
index.add(1, "Technology company announces revolutionary product")
index.add(2, "Technology company announces revolutionary update")

# Query for similar documents
candidates = index.query("Technology company announces")
# candidates is Set(Int32) of doc IDs

# Query with similarity scores
scored = index.query_with_scores("Technology company announces")
scored.each do |doc_id, score|
  puts "#{doc_id}: #{score}"
end

# Find all similar pairs above threshold
pairs = index.find_similar_pairs(threshold: 0.75)

# Monitor table utilization
puts index.load_factors  # Array(Float64) per band

# Storage operations
bytes = LexisMinhash::Engine.signature_to_bytes(sig)
restored = LexisMinhash::Engine.bytes_to_signature(bytes)
```

### Custom Document Types (Backward Compatibility)

```crystal
# Implement Document interface for custom types
struct MyDocument
  include LexisMinhash::Document

  getter text : String

  def initialize(@text : String)
  end
end

doc = MyDocument.new("Custom document text")
sig = LexisMinhash::Engine.compute_signature(doc)
```

## Configuration

```crystal
LexisMinhash::Engine.configure(
  signature_size: 100,  # Number of hash functions
  num_bands: 20,        # Number of bands for LSH
  shingle_size: 5       # Character shingle size
)
```

Default values:
- `signature_size`: 100
- `num_bands`: 20
- `rows_per_band`: 5 (calculated as signature_size / num_bands)
- `shingle_size`: 5

## Performance

Using rolling hash + multiply-shift:

```
Engine.compute_signature   1.95k (512µs)  2.66kB/op
```

### LSH Parameter Tuning

For 100 hashes targeting 0.75 similarity:

| Bands (b) | Rows (r) | Threshold | Prob @ Target |
|-----------|----------|-----------|---------------|
| 10        | 10       | 0.794     | 43.99%        |
| 20        | 5        | 0.549     | 99.56%        |
| 25        | 4        | 0.447     | 99.99%        |

Default (20 bands, 5 rows) gives 99.56% detection at 0.75 similarity.

Run benchmarks: `crystal run benchmark/benchmark.cr --release`

## API Reference

### Engine Methods

| Method | Description |
|--------|-------------|
| `compute_signature(text : String)` | Generate MinHash signature |
| `compute_signature(doc : Document)` | Generate signature from Document interface |
| `similarity(sig1, sig2)` | Compare two signatures (0.0 to 1.0) |
| `generate_bands(signature)` | Generate LSH bands, returns `Array({Int32, UInt64})` |
| `detection_probability(similarity)` | Probability of detecting items at given similarity |
| `signature_to_bytes(signature)` | Convert signature to bytes for storage |
| `bytes_to_signature(bytes)` | Convert bytes back to `Slice(UInt32)` |
| `bytes_to_signature_array(bytes)` | Convert bytes back to `Array(UInt32)` (compat) |

### LSHIndex Methods

| Method | Description |
|--------|-------------|
| `add(doc_id : Int32, text : String)` | Add document to index |
| `add_with_signature(doc_id, signature)` | Add with pre-computed signature |
| `query(text : String)` | Find candidate doc IDs |
| `query_by_signature(signature)` | Query with pre-computed signature |
| `query_with_scores(text)` | Query with similarity scores |
| `find_similar_pairs(threshold)` | Find all similar pairs |
| `get_signature(doc_id)` | Get stored signature |
| `load_factors` | Table utilization per band |
| `size` | Number of indexed documents |
| `clear` | Clear all data |

## Development

```bash
# Run tests
crystal spec

# Run linter
bin/ameba

# Run benchmarks
crystal run benchmark/benchmark.cr --release
```

## Contributing

1. Fork it (<https://github.com/kritoke/lexis-minhash/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## License

MIT
