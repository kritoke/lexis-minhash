# Lexis MinHash - Locality-Sensitive Hashing for text similarity detection
# Used to group duplicate or similar documents from various sources
require "digest/sha256"
require "set"
require "mutex"

# The main module containing all Lexis MinHash functionality
module LexisMinhash
  # The Document interface that must be implemented by any document type
  # that wants to use the Lexis MinHash engine.
  module Document
    # Returns the text content of the document for signature calculation
    abstract def text : String
  end

  # Default implementation of the Document interface for simple text strings
  struct SimpleDocument
    include Document

    getter text : String

    def initialize(@text : String)
    end
  end

  # Configuration for the MinHash engine
  struct Config
    getter signature_size : Int32
    getter num_bands : Int32
    getter shingle_size : Int32
    getter min_words : Int32
    getter stop_words : Set(String)

    def initialize(
      @signature_size : Int32 = 100,
      @num_bands : Int32 = 20,
      @shingle_size : Int32 = 3,
      @min_words : Int32 = 6,
      @stop_words : Set(String) = Set(String).new,
    )
    end

    def rows_per_band : Int32
      @signature_size // @num_bands
    end
  end

  # Default stop words for clustering
  DEFAULT_STOP_WORDS = Set.new([
    "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for",
    "of", "with", "by", "from", "as", "is", "was", "are", "were", "been",
    "be", "have", "has", "had", "do", "does", "did", "will", "would",
    "could", "should", "may", "might", "must", "shall", "can", "need",
    "this", "that", "these", "those", "it", "its", "they", "them",
    "time", "times", "day", "days", "week", "weeks", "month", "months",
    "year", "years", "today", "yesterday", "tomorrow", "morning", "afternoon", "evening",
    "new", "news", "latest", "update", "updates", "report", "reports",
    "breaking", "exclusive", "special", "alert", "alerts", "coverage",
    "says", "said", "saying", "tell", "tells", "told", "claim", "claims", "claimed",
    "just", "now", "how", "what", "when", "where", "why", "also", "too",
    "up", "down", "out", "over", "after", "before", "between", "under", "above",
    "one", "two", "three", "first", "second", "third", "top", "bottom",
    "get", "gets", "got", "make", "makes", "made", "take", "takes", "took",
    "see", "sees", "saw", "know", "knows", "knew", "think", "thinks", "thought",
    "want", "wants", "use", "uses", "used", "find", "finds", "found",
    "build", "building", "built", "using", "via", "making", "way",
    "youre", "your", "work", "works", "working",
  ])

  # The main engine for MinHash and LSH operations
  module Engine
    # Default configuration constants (for backward compatibility)
    SIGNATURE_SIZE           = 100
    NUM_BANDS                =  20
    ROWS_PER_BAND            = SIGNATURE_SIZE // NUM_BANDS
    SHINGLE_SIZE             =    3
    MIN_WORDS_FOR_CLUSTERING =    6
    SIMILARITY_THRESHOLD     = 0.75
    SHORT_HEADLINE_THRESHOLD = 0.85

    @@config : Config = Config.new
    @@hash_coeffs : Array(UInt32) = [] of UInt32
    @@mutex = Mutex.new

    def self.config : Config
      @@mutex.synchronize do
        ensure_initialized
        @@config
      end
    end

    private def self.ensure_initialized
      if @@hash_coeffs.empty?
        @@hash_coeffs = generate_hash_coeffs(@@config.signature_size)
      end
    end

    def self.configure(
      signature_size : Int32 = 100,
      num_bands : Int32 = 20,
      shingle_size : Int32 = 3,
      min_words : Int32 = 6,
      stop_words : Set(String) = DEFAULT_STOP_WORDS,
    ) : Nil
      @@mutex.synchronize do
        @@config = Config.new(
          signature_size: signature_size,
          num_bands: num_bands,
          shingle_size: shingle_size,
          min_words: min_words,
          stop_words: stop_words
        )
        @@hash_coeffs = generate_hash_coeffs(signature_size)
      end
    end

    private def self.generate_hash_coeffs(count : Int32) : Array(UInt32)
      count.times.map do
        Random::Secure.rand(UInt32)
      end.to_a
    end

    def self.reset_config : Nil
      @@mutex.synchronize do
        @@config = Config.new
        @@hash_coeffs = generate_hash_coeffs(@@config.signature_size)
      end
    end

    # Compute MinHash signature for a document
    # Uses true MinHash with k random hash functions
    def self.compute_signature(document : Document) : Array(UInt32)
      config, hash_coeffs = config_and_coeffs
      normalized = document.text.downcase.strip
      return Array(UInt32).new(config.signature_size, 0_u32) if normalized.empty?

      word_count = normalized.split(/\s+/).size
      return Array(UInt32).new(config.signature_size, 0_u32) if word_count < config.min_words

      filtered_text = remove_stop_words(normalized, config.stop_words)
      filtered_word_count = filtered_text.split(/\s+/).size
      return Array(UInt32).new(config.signature_size, 0_u32) if filtered_word_count < 2

      shingles = generate_shingles(filtered_text, config.shingle_size)
      return Array(UInt32).new(config.signature_size, 0_u32) if shingles.empty?

      compute_true_minhash(shingles, hash_coeffs)
    end

    private def self.config_and_coeffs : {Config, Array(UInt32)}
      @@mutex.synchronize do
        ensure_initialized
        {@@config, @@hash_coeffs.dup}
      end
    end

    private def self.current_config : Config
      @@mutex.synchronize do
        ensure_initialized
        @@config
      end
    end

    private def self.compute_true_minhash(shingles : Array(String), hash_coeffs : Array(UInt32)) : Array(UInt32)
      hash_coeffs.map do |seed|
        min_val = UInt32::MAX
        shingles.each do |shingle|
          h = seed_hash(shingle, seed)
          min_val = h if h < min_val
        end
        min_val
      end
    end

    private def self.sha256_hash(input : String) : UInt64
      hash = Digest::SHA256.digest(input)
      slice = hash.to_slice
      slice[0].to_u64 |
        (slice[1].to_u64 << 8) |
        (slice[2].to_u64 << 16) |
        (slice[3].to_u64 << 24) |
        (slice[4].to_u64 << 32) |
        (slice[5].to_u64 << 40) |
        (slice[6].to_u64 << 48) |
        (slice[7].to_u64 << 56)
    end

    private def self.seed_hash(input : String, seed : UInt64) : UInt32
      combined = "#{seed}#{input}"
      hash = Digest::SHA256.digest(combined)
      slice = hash.to_slice
      slice[0].to_u32 |
        (slice[1].to_u32 << 8) |
        (slice[2].to_u32 << 16) |
        (slice[3].to_u32 << 24)
    end

    private def self.remove_stop_words(text : String, stop_words : Set(String)) : String
      words = text.split(/\s+/)
      filtered = words.reject { |word| stop_words.includes?(word) }
      filtered.join(" ")
    end

    private def self.generate_shingles(text : String, size : Int32) : Array(String)
      return [] of String if text.size < size

      (0...(text.size - size + 1)).map do |i|
        text[i...i + size]
      end
    end

    def self.jaccard_similarity(doc1 : Document, doc2 : Document) : Float64
      set1 = shingles_to_set(doc1)
      set2 = shingles_to_set(doc2)
      return 0.0_f64 if set1.empty? && set2.empty?

      intersection = set1 & set2
      union = set1 | set2
      return 0.0_f64 if union.empty?

      intersection.size.to_f64 / union.size.to_f64
    end

    private def self.shingles_to_set(document : Document) : Set(UInt64)
      config = current_config
      normalized = document.text.downcase.strip
      return Set(UInt64).new if normalized.empty?

      word_count = normalized.split(/\s+/).size
      return Set(UInt64).new if word_count < config.min_words

      filtered_text = remove_stop_words(normalized, config.stop_words)
      filtered_word_count = filtered_text.split(/\s+/).size
      return Set(UInt64).new if filtered_word_count < 2

      shingles = generate_shingles(filtered_text, config.shingle_size)
      shingles.map { |shingle| sha256_hash(shingle) }.to_set
    end

    def self.compare(doc1 : Document, doc2 : Document) : Float64
      sig1 = compute_signature(doc1)
      sig2 = compute_signature(doc2)
      similarity(sig1, sig2)
    end

    def self.similarity(sig1 : Array(UInt32), sig2 : Array(UInt32)) : Float64
      return 0.0_f64 if sig1.empty? || sig2.empty?

      matches = 0
      sig1.each_with_index do |val1, idx|
        matches += 1 if val1 == sig2[idx]?
      end

      matches.to_f64 / sig1.size.to_f64
    end

    def self.shared_bands(sig1 : Array(UInt32), sig2 : Array(UInt32)) : Int32
      return 0 if sig1.empty? || sig2.empty?

      bands1 = generate_bands(sig1).to_set
      bands2 = generate_bands(sig2).to_set
      (bands1 & bands2).size
    end

    def self.generate_bands(signature : Array(UInt32)) : Array({Int32, UInt64})
      config = current_config
      rows_per_band = config.rows_per_band
      bands = [] of {Int32, UInt64}

      config.num_bands.times do |band_index|
        start_idx = band_index * rows_per_band
        end_idx = start_idx + rows_per_band

        band_hashes = signature[start_idx...end_idx]
        band_hash = combine_hashes(band_hashes)

        bands << {band_index, band_hash}
      end

      bands
    end

    private def self.combine_hashes(hashes : Array(UInt32)) : UInt64
      combined = 0_u64
      hashes.each do |hash_val|
        combined = (combined << 7) ^ hash_val
      end
      combined
    end

    def self.detection_probability(similarity : Float64) : Float64
      config = current_config
      s_r = similarity ** config.rows_per_band
      1.0_f64 - (1.0_f64 - s_r) ** config.num_bands
    end

    def self.signature_to_bytes(signature : Array(UInt32)) : Bytes
      bytes = Bytes.new(signature.size * sizeof(UInt32))
      signature.each_with_index do |val, idx|
        bytes[idx * sizeof(UInt32) + 0] = (val & 0xFF).to_u8
        bytes[idx * sizeof(UInt32) + 1] = ((val >> 8) & 0xFF).to_u8
        bytes[idx * sizeof(UInt32) + 2] = ((val >> 16) & 0xFF).to_u8
        bytes[idx * sizeof(UInt32) + 3] = ((val >> 24) & 0xFF).to_u8
      end
      bytes
    end

    def self.bytes_to_signature(bytes : Bytes) : Array(UInt32)
      return Array(UInt32).new if bytes.empty?

      signature = [] of UInt32
      (bytes.size // sizeof(UInt32)).times do |idx|
        val = bytes[idx * sizeof(UInt32) + 0].to_u32 |
              (bytes[idx * sizeof(UInt32) + 1].to_u32 << 8) |
              (bytes[idx * sizeof(UInt32) + 2].to_u32 << 16) |
              (bytes[idx * sizeof(UInt32) + 3].to_u32 << 24)
        signature << val
      end
      signature
    end
  end

  # In-memory LSH index for efficient candidate retrieval
  class LSHIndex
    @buckets : Hash(UInt64, Set(String))
    @signatures : Hash(String, Array(UInt32))

    def initialize
      @buckets = Hash(UInt64, Set(String)).new
      @signatures = Hash(String, Array(UInt32)).new
    end

    def add(doc_id : String, document : Document) : Nil
      signature = Engine.compute_signature(document)
      @signatures[doc_id] = signature
      bands = Engine.generate_bands(signature)
      bands.each do |_band_index, band_hash|
        @buckets[band_hash] ||= Set(String).new
        @buckets[band_hash] << doc_id
      end
    end

    def query(document : Document, max_candidates : Int32 = 100) : Set(String)
      signature = Engine.compute_signature(document)
      query_by_signature(signature, max_candidates)
    end

    def query_by_signature(signature : Array(UInt32), max_candidates : Int32 = 100) : Set(String)
      bands = Engine.generate_bands(signature)
      candidates = Set(String).new

      bands.each do |_band_index, band_hash|
        if bucket = @buckets[band_hash]
          candidates.concat(bucket)
        end
        break if candidates.size >= max_candidates
      end

      candidates
    end

    def query_with_scores(document : Document, max_candidates : Int32 = 100) : Array({String, Float64})
      signature = Engine.compute_signature(document)
      query_with_scores_by_signature(signature, max_candidates)
    end

    def query_with_scores_by_signature(signature : Array(UInt32), max_candidates : Int32 = 100) : Array({String, Float64})
      candidates = query_by_signature(signature, max_candidates)

      candidates.map do |doc_id|
        other_sig = @signatures[doc_id]?
        score = other_sig ? Engine.similarity(signature, other_sig) : 0.0_f64
        {doc_id, score}
      end.sort_by! { |_doc, score| -score }
    end

    def find_similar_pairs(threshold : Float64 = 0.75) : Set({String, String})
      pairs = Set({String, String}).new
      checked = Set({String, String}).new

      @signatures.each do |doc_id, signature|
        candidates = query_by_signature(signature, max_candidates: 50)

        candidates.each do |other_id|
          next if doc_id == other_id
          pair_key = doc_id < other_id ? {doc_id, other_id} : {other_id, doc_id}
          next if checked.includes?(pair_key)
          checked << pair_key

          if other_sig = @signatures[other_id]?
            if Engine.similarity(signature, other_sig) >= threshold
              pairs << {doc_id, other_id}
            end
          end
        end
      end

      pairs
    end

    def size : Int32
      @signatures.size
    end

    def clear : Nil
      @buckets.clear
      @signatures.clear
    end
  end
end
