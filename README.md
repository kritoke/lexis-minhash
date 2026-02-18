# Lexis MinHash

Lexis MinHash is a locality-sensitive hashing (LSH) library for detecting similar text documents using the MinHash technique. It uses rolling hash + multiply-shift for O(n) performance.

## Features

- **O(n) MinHash Signatures**: Rolling hash + multiply-shift, no intermediate string allocations
- **Signature Similarity**: Fast approximate Jaccard similarity estimation
- **Overlap Coefficient**: Measure set similarity using |A ∩ B| / min(|A|, |B|)
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

### Overlap Coefficient

The overlap coefficient measures set similarity as `|A ∩ B| / min(|A|, |B|)`. Unlike Jaccard similarity (|A ∩ B| / |A ∪ B|), it's better at detecting partial overlaps when one set is a subset of another.

```crystal
# Works with sorted UInt32 or UInt64 slices
a = Slice.new(5) { |i| (i * 2).to_u32 }  # [0, 2, 4, 6, 8]
b = Slice.new(3) { |i| (i * 2 + 2).to_u32 }  # [2, 4, 6]

# Intersection: [2, 4, 6] = 3 elements
# min(5, 3) = 3
# Overlap coefficient = 3/3 = 1.0
coefficient = LexisMinhash::Engine.overlap_coefficient(a, b)
puts "Overlap: #{coefficient}"  # => 1.0
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
  shingle_size: 5,      # Character shingle size
  min_words: 4          # Minimum words to produce signature (below = zeros)
)
```

Default values:
- `signature_size`: 100
- `num_bands`: 20
- `rows_per_band`: 5 (calculated as signature_size / num_bands)
- `shingle_size`: 5
- `min_words`: 4 (texts with fewer words return zero signature)

### Minimum Words Threshold

Texts with fewer than `min_words` return a zero signature:

```crystal
LexisMinhash::Engine.compute_signature("Short")        # => [0, 0, 0, ...] (1 word)
LexisMinhash::Engine.compute_signature("Hello world")  # => [0, 0, 0, ...] (2 words)
LexisMinhash::Engine.compute_signature("Bitcoin price surge continues")  # => [...] (4 words, produces signature)
```

This prevents clustering meaningless short headlines. Adjust based on your use case:

```crystal
LexisMinhash::Engine.configure(min_words: 6)  # Stricter filtering
```

## Performance

Using rolling hash + multiply-shift:

```
compute_signature (Array)       528µs  5.0kB/op
compute_signature_slice         512µs  2.66kB/op  (recommended)
```

**Note:** Default methods return `Array(UInt32)` for backward compatibility (~3% slower, 2x memory). Use `compute_signature_slice` and `bytes_to_signature_slice` for maximum performance.

### LSH Parameter Tuning

For 100 hashes targeting 0.75 similarity:

| Bands (b) | Rows (r) | Threshold | Prob @ Target |
|-----------|----------|-----------|---------------|
| 10        | 10       | 0.794     | 43.99%        |
| 20        | 5        | 0.549     | 99.56%        |
| 25        | 4        | 0.447     | 99.99%        |

Default (20 bands, 5 rows) gives 99.56% detection at 0.75 similarity.

### Important: Randomized Hashing

MinHash uses randomized hash functions. This means:

- **Absolute similarity values vary between runs** - The same two documents may get slightly different similarity scores each time the program starts
- **Use relative comparisons in tests** - Prefer `similarity(a, b) > similarity(a, c)` over `similarity(a, b) > 0.5`
- **Deterministic within a run** - Once initialized, the same text always produces the same signature

```crystal
# Good for tests - relative comparison
sim_similar = Engine.similarity(sig1, sig2)
sim_different = Engine.similarity(sig1, sig3)
sim_similar.should be > sim_different

# Brittle in tests - absolute threshold
Engine.similarity(sig1, sig2).should be > 0.3  # May fail due to randomization
```

Run benchmarks: `crystal run benchmark/benchmark.cr --release`

## API Reference

### Engine Methods

| Method | Description |
|--------|-------------|
| `compute_signature(text : String)` | Generate MinHash signature → `Array(UInt32)` |
| `compute_signature(doc : Document)` | Generate from Document interface → `Array(UInt32)` |
| `compute_signature_slice(text)` | Generate signature → `Slice(UInt32)` (faster) |
| `similarity(sig1, sig2)` | Compare two signatures (0.0 to 1.0) |
| `overlap_coefficient(a, b)` | Overlap coefficient: \|A ∩ B\| / min(\|A\|, \|B\|) |
| `generate_bands(signature)` | Generate LSH bands → `Array({Int32, UInt64})` |
| `detection_probability(similarity)` | Probability of detecting items at given similarity |
| `signature_to_bytes(signature)` | Convert signature to bytes for storage |
| `bytes_to_signature(bytes)` | Convert bytes → `Array(UInt32)` |
| `bytes_to_signature_slice(bytes)` | Convert bytes → `Slice(UInt32)` (faster) |

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
