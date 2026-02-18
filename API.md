# Lexis MinHash - Advanced Usage Guide

This guide covers advanced patterns and recommendations for using lexis-minhash in production applications.

## Table of Contents

1. [Weighting Strategies](#weighting-strategies)
2. [Text Preprocessing](#text-preprocessing)
3. [Performance Optimization](#performance-optimization)
4. [Custom Similarity Functions](#custom-similarity-functions)
5. [Common Patterns](#common-patterns)

---

## Weighting Strategies

The library provides a basic weighted MinHash implementation where higher weights make rare terms more influential. For production use, you may want different weighting schemes:

### TF-IDF Weights

Compute term frequency-inverse document frequency externally:

```crystal
# Client-side: compute TF-IDF scores
def compute_tfidf(documents : Array(String), term : String, doc_index : Int32) : Float64
  tf = term_frequency(documents[doc_index], term)
  idf = inverse_document_frequency(documents, term)
  tf * idf
end

# Then use with library
weights = Hash(String, Float64).new(1.0_f64)
all_documents.each_with_index do |doc, i|
  unique_terms(doc).each do |term|
    weights[term] = compute_tfidf(all_documents, term, i)
  end
end

signature = LexisMinhash::Engine.compute_signature(document, weights)
```

### Log-Transformed Weights

Apply log transformation to reduce impact of very high frequencies:

```crystal
def log_weight(term_frequency : Float64) : Float64
  Math.log(1.0_f64 + term_frequency)
end
```

### BM25-Style Weights

For more sophisticated relevance scoring:

```crystal
def bm25_weight(
  term_freq : Float64,
  doc_length : Float64,
  avg_doc_length : Float64,
  idf : Float64,
  k1 : Float64 = 1.5,
  b : Float64 = 0.75
) : Float64
  numerator = term_freq * (k1 + 1.0_f64)
  denominator = term_freq + k1 * (1.0_f64 - b + b * doc_length / avg_doc_length)
  idf * (numerator / denominator)
end
```

---

## Text Preprocessing

The library operates on character shingles with minimal preprocessing. Handle advanced normalization client-side:

### Stemming and Lemmatization

```crystal
# Before computing signature
def preprocess(text : String) : String
  # Apply stemming (e.g., using a stemmer library)
  # Example: "running" -> "run", "computers" -> "computer"
  text
end

sig = LexisMinhash::Engine.compute_signature(preprocess(original_text))
```

### Stop Word Removal

```crystal
STOP_WORDS = Set.new(["the", "a", "an", "is", "are", "was", "were", "of", "in", "on", "at", "to", "for"])

def remove_stop_words(text : String) : String
  text.split.select { |word| !STOP_WORDS.includes?(word.downcase) }.join(" ")
end
```

### N-gram Variations

```crystal
# Word n-grams instead of character n-grams
def word_shingles(text : String, n : Int32 = 3) : Array(String)
  words = text.downcase.split
  return [] of String if words.size < n
  words.each_cons(n).map(&.join(" ")).to_a
end
```

---

## Performance Optimization

### Caching Shingle Weights

Pre-compute weights to avoid repeated string operations:

```crystal
class CachedWeightCalculator
  @cache : Hash(String, Hash(String, Float64)) = Hash(String, Hash(String, Float64)).new

  def get_weights(text : String, base_weights : Hash(String, Float64)) : Hash(String, Float64)
    @cache[text] ||= begin
      cache = Hash(String, Float64).new(1.0_f64)
      normalized = text.downcase
      (normalized.size - 4).times do |i|
        shingle = normalized[i...i + 5]
        cache[shingle] = base_weights[shingle]? || 1.0_f64
      end
      cache
    end
  end
end
```

### Batch Processing

Process multiple documents efficiently:

```crystal
def compute_signatures_batch(texts : Array(String)) : Array(Array(UInt32))
  texts.map { |text| LexisMinhash::Engine.compute_signature(text) }
end

# Or with parallelization using fibers
def compute_signatures_parallel(texts : Array(String)) : Array(Array(UInt32))
  channels = Array(Channel(Array(UInt32))).new

  texts.each_with_index do |text, i|
    channel = Channel(Array(UInt32)).new
    channels << channel

    spawn do
      channel.send(LexisMinhash::Engine.compute_signature(text))
    end
  end

  channels.map(&.receive)
end
```

### Slice Over Array

Use Slice for better memory performance:

```crystal
# Instead of Array(UInt32)
sig = LexisMinhash::Engine.compute_signature_slice(text)  # Returns Slice(UInt32)

# Store as bytes for persistence
bytes = LexisMinhash::Engine.signature_to_bytes(sig)
```

---

## Custom Similarity Functions

### Weighted Jaccard for Weighted Sets

```crystal
module CustomSimilarity
  def self.weighted_jaccard(
    a : Hash(String, Float64),
    b : Hash(String, Float64)
  ) : Float64
    return 0.0_f64 if a.empty? && b.empty?
    return 0.0_f64 if a.empty? || b.empty?

    intersection = 0.0_f64
    union = 0.0_f64

    all_keys = a.keys + b.keys
    all_keys.uniq!.each do |key|
      weight_a = a[key]? || 0.0_f64
      weight_b = b[key]? || 0.0_f64

      intersection += Math.min(weight_a, weight_b)
      union += Math.max(weight_a, weight_b)
    end

    union > 0.0_f64 ? intersection / union : 0.0_f64
  end

  def self.cosine_similarity(
    a : Hash(String, Float64),
    b : Hash(String, Float64)
  ) : Float64
    dot_product = 0.0_f64
    magnitude_a = 0.0_f64
    magnitude_b = 0.0_f64

    all_keys = a.keys + b.keys
    all_keys.uniq!.each do |key|
      weight_a = a[key]? || 0.0_f64
      weight_b = b[key]? || 0.0_f64

      dot_product += weight_a * weight_b
      magnitude_a += weight_a * weight_a
      magnitude_b += weight_b * weight_b
    end

    magnitude = Math.sqrt(magnitude_a) * Math.sqrt(magnitude_b)
    magnitude > 0.0_f64 ? dot_product / magnitude : 0.0_f64
  end
end
```

### Document-Level Weighted Signatures

```crystal
# Combine MinHash signature with weighted overlap for hybrid similarity
def hybrid_similarity(
  sig1 : Array(UInt32),
  sig2 : Array(UInt32),
  weights1 : Hash(String, Float64),
  weights2 : Hash(String, Float64),
  minhash_weight : Float64 = 0.7_f64
) : Float64
  minhash_sim = LexisMinhash::Engine.similarity(sig1, sig2)
  weighted_sim = LexisMinhash::Similarity.weighted_overlap(weights1, weights2)

  (minhash_weight * minhash_sim) + ((1.0_f64 - minhash_weight) * weighted_sim)
end
```

---

## Common Patterns

### Document Deduplication

```crystal
def find_duplicates(documents : Array({Int32, String}), threshold : Float64 = 0.8_f64)
  index = LexisMinhash::LSHIndex.new(bands: 20, expected_docs: documents.size)

  duplicates = [] of Array(Int32)

  documents.each do |id, text|
    candidates = index.query(text)

    candidates.each do |candidate_id|
      next if candidate_id >= id

      existing_sig = index.get_signature(candidate_id)
      if existing_sig
        current_sig = LexisMinhash::Engine.compute_signature(text)
        if LexisMinhash::Engine.similarity(existing_sig, current_sig) >= threshold
          duplicates << [candidate_id, id]
        end
      end
    end

    index.add(id, text)
  end

  duplicates
end
```

### Nearest Neighbor Search

```crystal
def find_nearest(
  query : String,
  documents : Array({Int32, String}),
  k : Int32 = 5
) : Array({Int32, Float64})
  index = LexisMinhash::LSHIndex.new(bands: 20, expected_docs: documents.size)

  documents.each_with_index do |(id, text), i|
    index.add(id, text)
  end

  results = index.query_with_scores(query)
  results.first(k)
end
```

### Incremental Indexing

```crystal
class IncrementalIndexer
  @index : LexisMinhash::LSHIndex
  @doc_count : Int32 = 0

  def initialize(bands : Int32 = 20, initial_capacity : Int32 = 1000)
    @index = LexisMinhash::LSHIndex.new(bands: bands, expected_docs: initial_capacity)
  end

  def add_document(text : String) : Int32
    id = @doc_count
    @index.add(id, text)
    @doc_count += 1
    id
  end

  def reindex_with_weights(weights_factory : String -> Hash(String, Float64))
    @index.clear
    @doc_count = 0
    # Re-add with new weights - implement based on your storage
  end
end
```

---

## See Also

- [README.md](../README.md) - Basic usage and API reference
- [Crystal Docs](https://crystal-lang.org/api/) - Crystal standard library
