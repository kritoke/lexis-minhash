# Engine implementation and core types for LexisMinhash
#
# Contains the main engine: MinHash signature generation (weighted and
# unweighted), band generation for LSH, and similarity estimation.
# Configuration is in engine/config.cr, rolling hash in engine/rolling.cr,
# signature helpers in engine/signature.cr, serialization in engine/serialize.cr.
require "./engine/config"
require "./engine/rolling"
require "./engine/signature"
require "./engine/serialize"

module LexisMinhash
  # MinHash signature wrapper providing convenient serialization and similarity
  #
  # Example:
  # ```
  # sig = LexisMinhash::Signature.compute("Document text")
  # bytes = sig.to_blob
  # sig2 = LexisMinhash::Signature.from_blob(bytes)
  # sim = sig.similarity(sig2)
  # ```
  struct Signature
    getter data : Slice(UInt32)

    # Initialize from a pre-allocated Slice(UInt32).
    # Prefer `Signature.compute` for common usage.
    def initialize(@data : Slice(UInt32))
    end

    # Compute signature for a plain String using the Engine's default configuration
    def self.compute(text : String) : Signature
      Signature.new(Engine.compute_signature_slice(text))
    end

    # Compute signature for a String with optional TF-IDF style weights
    def self.compute(text : String, weights : Hash(String, Float64)?) : Signature
      Signature.new(Engine.compute_signature_slice(text, weights))
    end

    # Serialize signature to raw bytes suitable for storage (e.g., SQLite BLOB)
    def to_blob : Bytes
      @data.to_unsafe.as(UInt8*).to_slice(@data.size * sizeof(UInt32))
    end

    # Deserialize a BLOB back into a Signature. Raises ArgumentError for malformed input.
    def self.from_blob(blob : Bytes) : Signature
      return Signature.new(Slice(UInt32).new(0)) if blob.empty?

      if blob.size % sizeof(UInt32) != 0
        raise ArgumentError.new("Invalid blob size: must be a multiple of #{sizeof(UInt32)} bytes")
      end

      count = blob.size // sizeof(UInt32)
      slice = Slice(UInt32).new(count)
      blob.copy_to(slice.to_unsafe.as(UInt8*), blob.size)
      Signature.new(slice)
    end

    # Compute similarity against another Signature
    def similarity(other : Signature) : Float64
      Engine.similarity(@data, other.data)
    end

    # Number of hash values contained in this signature
    def size : Int32
      @data.size
    end
  end

  # MinHash engine using rolling hash + multiply-shift
  # O(n) shingling with no intermediate string allocations
  module Engine
    # Default configuration constants
    SIGNATURE_SIZE   =     100
    NUM_BANDS        =      20
    ROWS_PER_BAND    =       5
    SHINGLE_SIZE     =       5
    MIN_WORDS        =       4
    DEFAULT_WEIGHT   = 1.0_f64
    MAX_SHINGLE_SIZE =      32

    # --- Private helpers to eliminate DRY violations ---

    # Normalize text and validate against config requirements.
    # Returns the normalized text, or nil if it doesn't meet minimum criteria.
    private def self.prepare_text(text : String, cfg : Config) : String?
      normalized = text.downcase.strip
      return nil if normalized.empty?
      word_count = normalized.split(/\s+/).size
      return nil if word_count < cfg.min_words
      return nil if normalized.size < cfg.shingle_size
      normalized
    end

    # Apply a single shingle hash to the signature using multiply-shift.
    # Updates signature[i] = min(signature[i], hash(a[i], b[i], h64)).
    private def self.apply_hash_min(signature : Slice(UInt32), h64 : UInt64, cfg : Config) : Nil
      num_hashes = cfg.signature_size
      a = cfg.a
      b = cfg.b
      num_hashes.times do |i|
        combined_h = ((a[i] &* h64 &+ b[i]) >> 32).to_u32
        signature[i] = combined_h if combined_h < signature[i]
      end
    end

    # Apply a weighted shingle hash to the signature.
    # Higher weights cause the hash to be divided, making it more likely to "win" the min.
    private def self.apply_weighted_hash_min(signature : Slice(UInt32), h64 : UInt64, weight : Float64, cfg : Config) : Nil
      effective_weight = normalize_weight(weight)
      return if effective_weight.nil?

      effective_value = effective_weight < 1.0_f64 ? Math.log(1.0_f64 + effective_weight) : effective_weight
      num_hashes = cfg.signature_size
      a = cfg.a
      b = cfg.b

      num_hashes.times do |i|
        combined_h = ((a[i] &* h64 &+ b[i]) >> 32).to_u32
        weighted_value = combined_h.to_f64 / effective_value
        weighted_h = (weighted_value % Float64.new(UInt32::MAX)).to_u32
        signature[i] = weighted_h if weighted_h < signature[i]
      end
    end

    # Clamp weight to non-negative; returns nil if weight should be excluded.
    private def self.normalize_weight(weight : Float64) : Float64?
      effective = Math.max(weight, 0.0_f64)
      return nil if effective <= 0.0_f64
      effective
    end

    # --- Public signature computation API ---

    # Compute signature using rolling hash + multiply-shift.
    # Returns Array(UInt32) for backward compatibility.
    def self.compute_signature(text : String) : Array(UInt32)
      compute_signature_with_config(default_config, text).to_a
    end

    # Compute signature as Slice(UInt32) for performance-critical code.
    def self.compute_signature_slice(text : String) : Slice(UInt32)
      compute_signature_with_config(default_config, text)
    end

    # Computes a MinHash signature with optional TF-IDF weights.
    # Unknown shingles use the configured default weight (default: 1.0).
    # Negative weights are clamped to 0 (excluded from signature).
    def self.compute_signature(text : String, weights : Hash(String, Float64)?) : Array(UInt32)
      if weights
        compute_signature_slice_weighted(text, weights).to_a
      else
        compute_signature(text)
      end
    end

    # Computes a weighted MinHash signature from String-keyed weights.
    def self.compute_signature_weighted(text : String, weights : Hash(String, Float64)) : Array(UInt32)
      compute_signature_slice_weighted(text, weights).to_a
    end

    # Compute weighted signature using hashed shingle keys (UInt64).
    def self.compute_signature(text : String, weights : Hash(UInt64, Float64)) : Array(UInt32)
      compute_signature_slice_weighted_hashed(text, weights).to_a
    end

    # Compute signature slice with optional String->Float64 weights.
    def self.compute_signature_slice(text : String, weights : Hash(String, Float64)?) : Slice(UInt32)
      if weights
        compute_signature_slice_weighted(text, weights)
      else
        compute_signature_slice(text)
      end
    end

    # Compute a weighted signature from String-keyed weights.
    # Pre-hashes the weights map once to avoid repeated String allocations.
    def self.compute_signature_slice_weighted(text : String, weights : Hash(String, Float64)) : Slice(UInt32)
      hashed_weights = prehash_weights(weights)
      compute_signature_slice_weighted_hashed(text, hashed_weights)
    end

    # Compute weighted signature where weights are keyed by the shingle's UInt64 rolling hash.
    def self.compute_signature_slice_weighted_hashed(text : String, weights_hashed : Hash(UInt64, Float64)) : Slice(UInt32)
      cfg = default_config
      num_hashes = cfg.signature_size

      normalized = prepare_text(text, cfg)
      return Slice(UInt32).new(num_hashes, 0_u32) if normalized.nil?

      signature = Slice(UInt32).new(num_hashes, UInt32::MAX)
      def_weight = cfg.default_weight

      roller = ShingleRoller.new(cfg.shingle_size)
      normalized.each_byte do |byte|
        if h64 = roller.roll(byte)
          weight = weights_hashed[h64]? || def_weight
          apply_weighted_hash_min(signature, h64, weight, cfg)
        end
      end

      signature
    end

    # --- Hash-based signature API (decoupled from text processing) ---

    # Compute signature directly from pre-hashed UInt64 values.
    # The application handles String → UInt64 conversion.
    def self.compute_signature_from_hashes(hashes : Iterable(UInt64)) : Slice(UInt32)
      cfg = default_config
      signature = Slice(UInt32).new(cfg.signature_size, UInt32::MAX)
      hashes.each do |h64|
        apply_hash_min(signature, h64, cfg)
      end
      signature
    end

    # Compute weighted signature from parallel iterables of hashes and weights.
    def self.compute_signature_from_hashes(hashes : Iterable(UInt64), weights : Iterable(Float64)) : Slice(UInt32)
      cfg = default_config
      signature = Slice(UInt32).new(cfg.signature_size, UInt32::MAX)
      hashes.zip(weights).each do |h64, weight|
        apply_weighted_hash_min(signature, h64, weight, cfg)
      end
      signature
    end

    # --- Weight prehashing helpers ---

    # Compute the rolling UInt64 hash for a given shingle String.
    def self.shingle_hash_for(shingle : String) : UInt64
      roller = ShingleRoller.new(shingle.size)
      h = 0_u64
      shingle.each_byte do |byte|
        if hh = roller.roll(byte)
          h = hh
        end
      end
      h
    end

    # Convert String-keyed weights into UInt64-keyed weights using rolling shingle hash.
    def self.prehash_weights(weights : Hash(String, Float64)) : Hash(UInt64, Float64)
      hashed = Hash(UInt64, Float64).new
      weights.each do |shingle, weight|
        hashed[shingle_hash_for(shingle)] = weight
      end
      hashed
    end

    # Convenience: prehash String-keyed weights and compute signature.
    def self.compute_signature_with_prehashed_weights(text : String, weights : Hash(String, Float64)) : Array(UInt32)
      hashed = prehash_weights(weights)
      compute_signature_slice_weighted_hashed(text, hashed).to_a
    end

    # --- Similarity and comparison ---

    # Compute similarity between two signatures (Array or Slice)
    def self.similarity(sig1 : Array(UInt32) | Slice(UInt32), sig2 : Array(UInt32) | Slice(UInt32)) : Float64
      return 0.0_f64 if sig1.empty? || sig2.empty?
      return 0.0_f64 if sig1.size != sig2.size

      matches = 0
      sig1.size.times do |i|
        matches += 1 if sig1[i] == sig2[i]
      end

      matches.to_f64 / sig1.size.to_f64
    end

    # Extract shingle set from text as UInt64 hashes using rolling hash.
    private def self.extract_shingle_set(text : String) : Set(UInt64)
      cfg = default_config
      shingles = Set(UInt64).new

      normalized = text.downcase.strip
      return shingles if normalized.empty?
      return shingles if normalized.size < cfg.shingle_size

      roller = ShingleRoller.new(cfg.shingle_size)
      normalized.each_byte do |byte|
        if h64 = roller.roll(byte)
          shingles << h64
        end
      end

      shingles
    end

    # Compute true Jaccard similarity between two texts based on shingle sets.
    def self.jaccard_similarity(text1 : String, text2 : String) : Float64
      set1 = extract_shingle_set(text1)
      set2 = extract_shingle_set(text2)
      Similarity.jaccard(set1, set2)
    end

    # Compute true Jaccard similarity between two Documents.
    def self.jaccard_similarity(doc1 : LexisMinhash::Document, doc2 : LexisMinhash::Document) : Float64
      jaccard_similarity(doc1.text, doc2.text)
    end

    # Overlap coefficient for two sorted UInt64 slices.
    def self.overlap_coefficient(a : Slice(UInt64), b : Slice(UInt64)) : Float64
      Similarity.fast_overlap(a, b)
    end

    # Overlap coefficient for two sorted UInt32 slices.
    def self.overlap_coefficient(a : Slice(UInt32), b : Slice(UInt32)) : Float64
      Similarity.fast_overlap(a, b)
    end

    # --- LSH banding ---

    # Generate LSH bands from a signature (Array or Slice).
    # Returns Array({Int32, UInt64}) with {band_index, band_hash} tuples.
    def self.generate_bands(signature : Array(UInt32) | Slice(UInt32), bands : Int32? = nil) : Array({Int32, UInt64})
      cfg = default_config
      num_bands = bands || cfg.num_bands
      rows = cfg.rows_per_band
      band_hashes = [] of {Int32, UInt64}

      num_bands.times do |band_idx|
        combined = 0_u64
        rows.times do |j|
          combined = combine_hash(combined, signature[band_idx * rows + j])
        end
        band_hashes << {band_idx, combined}
      end

      band_hashes
    end

    # Estimate probability of detecting similar items.
    def self.detection_probability(similarity : Float64) : Float64
      cfg = default_config
      bands = cfg.num_bands
      rows = cfg.rows_per_band
      s_r = similarity ** rows
      1.0_f64 - (1.0_f64 - s_r) ** bands
    end

    # Robust hash combination using splitmix64-style mixing.
    private def self.combine_hash(combined : UInt64, hash_value : UInt32) : UInt64
      result = (combined ^ hash_value.to_u64) &* 0x9e3779b97f4a7c15_u64
      result = (result ^ (result >> 32))
      result
    end
  end
end
