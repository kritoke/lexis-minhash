# Engine implementation and core types for LexisMinhash
#
# This file contains the main engine implementation: rolling shingling,
# MinHash signature generation (weighted and unweighted), helpers for
# prehashing weights, and serialization helpers. The `Signature` struct is a
# convenient wrapper for signatures with to_blob/from_blob helpers.
require "./engine/config"
require "./engine/rolling"
require "./engine/signature"
require "./engine/serialize"

module LexisMinhash
  # ShingleRoller and shingles_hashes are implemented in engine/rolling.cr

  # MinHash signature wrapper providing convenient serialization and similarity
  #
  # Signature contains a `Slice(UInt32)` of minhash values and exposes helpers to
  # serialize to a BLOB (`to_blob`) and deserialize back (`from_blob`). It also
  # exposes `similarity` to compare two Signatures using the Engine implementation.
  #
  # Example
  # ```
  # sig = LexisMinhash::Signature.compute("Document text")
  # bytes = sig.to_blob
  # sig2 = LexisMinhash::Signature.from_blob(bytes)
  # sim = sig.similarity(sig2)
  # ```
  struct Signature
    getter data : Slice(UInt32)

    # Initialize a Signature wrapper from a pre-allocated `Slice(UInt32)`.
    # This is a low-level constructor used by other helpers; prefer
    # `Signature.compute` for common usage.
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
      # Cast the UInt32 slice to a raw Byte slice for SQLite BLOBs
      @data.to_unsafe.as(UInt8*).to_slice(@data.size * sizeof(UInt32))
    end

    # Deserialize a BLOB produced by `to_blob` back into a Signature. Returns an
    # empty Signature for empty blobs and raises `ArgumentError` for malformed input.
    def self.from_blob(blob : Bytes) : Signature
      return Signature.new(Slice(UInt32).new(0)) if blob.empty?

      if blob.size % sizeof(UInt32) != 0
        raise ArgumentError.new("Invalid blob size: must be a multiple of #{sizeof(UInt32)} bytes")
      end

      count = blob.size // sizeof(UInt32)
      slice = Slice(UInt32).new(count)
      # copy raw bytes into the UInt32 slice memory (copy as UInt8 pointer)
      blob.copy_to(slice.to_unsafe.as(UInt8*), blob.size)
      Signature.new(slice)
    end

    # Compute similarity against another Signature using Engine.similarity
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
    # Runtime mutable engine state was moved to engine/config.cr. Use
    # `default_config` and `configure` from there for deterministic setup.

    # Default configuration constants
    SIGNATURE_SIZE =     100
    NUM_BANDS      =      20
    ROWS_PER_BAND  =       5
    SHINGLE_SIZE   =       5
    MIN_WORDS      =       4
    DEFAULT_WEIGHT = 1.0_f64

    # Initialization and mutable coefficient state are handled in engine/config.cr

    # Config struct is provided in engine/config.cr (functional refactor)

    # Rolling shingle helper is provided by engine/rolling.cr

    # Engine configuration is implemented in `engine/config.cr` and exported
    # from there (provides `Engine.configure`, `Engine.config`, and `Engine.default_weight`).

    # Compute signature using rolling hash + multiply-shift
    # Returns Array(UInt32) for backward compatibility
    # This API is convenient but slower than `compute_signature_slice` which
    # returns a `Slice(UInt32)` directly for performance-critical code.
    def self.compute_signature(text : String) : Array(UInt32)
      # Back-compat: use default config to compute signature via the pure API
      cfg = default_config
      compute_signature_with_config(cfg, text).to_a
    end

    # Compute signature as Slice(UInt32) for performance-critical code
    def self.compute_signature_slice(text : String) : Slice(UInt32)
      cfg = default_config
      compute_signature_with_config(cfg, text)
    end

    private def self.update_signature(signature : Slice(UInt32), h64 : UInt64) : Nil
      # Use the runtime default configuration (thread-safe, from engine/config.cr)
      cfg = default_config
      num_hashes = cfg.signature_size
      a = cfg.a
      b = cfg.b
      num_hashes.times do |i|
        combined_h = ((a[i] &* h64 &+ b[i]) >> 32).to_u32
        signature[i] = combined_h if combined_h < signature[i]
      end
    end

    # Computes a MinHash signature with optional TF-IDF weights
    #
    # If weights are provided, uses weighted MinHash where higher weights
    # (rare terms) have more influence on the signature.
    #
    # ```
    # weights = {"hello" => 2.0_f64, "world" => 1.5_f64}
    # sig = LexisMinhash::Engine.compute_signature("Hello World", weights)
    # ```
    #
    # **Hash Key Matching**: Keys in the weights hash must match the shingles
    # generated from the text. The library uses character n-grams (default: 5 chars)
    # after converting text to lowercase. For example, "hello world" with shingle_size=5
    # generates shingles: "hello", "ello ", "llo w", "lo wo", "o wor", " worl", "world"
    #
    # Unknown shingles use the configured default weight (default: 1.0).
    # Set via `Engine.configure(default_weight: value)`.
    #
    # Negative weights are clamped to 0 (excluded from signature).
    def self.compute_signature(text : String, weights : Hash(String, Float64)?) : Array(UInt32)
      if weights
        # Back-compat: use default_config for weighted path as well
        cfg = default_config
        compute_signature_slice_weighted(text, weights).to_a
      else
        compute_signature(text)
      end
    end

    # Computes a weighted MinHash signature
    #
    # Higher weights make terms more influential by dividing their hash values.
    # This causes rare (high-weight) terms to produce smaller values that are
    # more likely to "win" the minimum hash position.
    def self.compute_signature_weighted(text : String, weights : Hash(String, Float64)) : Array(UInt32)
      compute_signature_slice_weighted(text, weights).to_a
    end

    # Compute weighted signature using hashed shingle keys to avoid building Strings per shingle
    def self.compute_signature(text : String, weights : Hash(UInt64, Float64)) : Array(UInt32)
      compute_signature_slice_weighted_hashed(text, weights).to_a
    end

    private def self.update_signature_weighted(signature : Slice(UInt32), h64 : UInt64, weight : Float64) : Nil
      # Use runtime default config coefficients
      cfg = default_config
      num_hashes = cfg.signature_size
      a = cfg.a
      b = cfg.b

      effective_weight = Math.max(weight, 0.0_f64)
      return if effective_weight <= 0.0_f64

      num_hashes.times do |i|
        combined_h = ((a[i] &* h64 &+ b[i]) >> 32).to_u32
        effective_value = effective_weight < 1.0_f64 ? Math.log(1.0_f64 + effective_weight) : effective_weight
        weighted_value = combined_h.to_f64 / effective_value
        weighted_h = (weighted_value % Float64.new(UInt32::MAX)).to_u32
        signature[i] = weighted_h if weighted_h < signature[i]
      end
    end

    # Compute signature slice (fast path) with optional String->Float64 weights.
    # Prefer this API for performance-sensitive code because it avoids Array
    # allocations and returns a Slice(UInt32) directly.
    def self.compute_signature_slice(text : String, weights : Hash(String, Float64)?) : Slice(UInt32)
      if weights
        compute_signature_slice_weighted(text, weights)
      else
        compute_signature_slice(text)
      end
    end

    # Compute a weighted signature where weights are provided as a String->Float map
    # The method allocates shingle Strings internally (one per shingle). For high
    # volume usage prefer `prehash_weights` + hashed-weight API to avoid
    # allocation overhead.
    def self.compute_signature_slice_weighted(text : String, weights : Hash(String, Float64)) : Slice(UInt32)
      # Implement weighted signature using default_config to preserve
      # runtime-configured coefficients if Engine.configure was used.
      cfg = default_config
      num_hashes = cfg.signature_size
      shingle_size = cfg.shingle_size
      min_words = cfg.min_words

      normalized = text.downcase.strip
      return Slice(UInt32).new(num_hashes, 0_u32) if normalized.empty?

      word_count = normalized.split(/\s+/).size
      return Slice(UInt32).new(num_hashes, 0_u32) if word_count < min_words

      return Slice(UInt32).new(num_hashes, 0_u32) if normalized.size < shingle_size

      signature = Slice(UInt32).new(num_hashes, UInt32::MAX)
      def_weight = cfg.default_weight

      # Use shingles_hashes but we need the shingle string to lookup weights.
      # Fall back to ShingleRoller for the small allocation where string keys are used.
      roller = ShingleRoller.new(shingle_size)
      normalized.each_byte do |byte|
        if h64 = roller.roll(byte)
          if shingle_str = roller.current_shingle
            weight = weights[shingle_str]? || def_weight
            update_signature_weighted(signature, h64, weight)
          end
        end
      end

      signature
    end

    # Compute weighted signature where weights are keyed by the shingle's UInt64 rolling hash.
    # This avoids allocating a String for every shingle and can significantly reduce
    # allocations when weights are provided.
    # Compute a weighted signature where weights are provided keyed by the
    # shingle's rolling hash (UInt64). This avoids per-shingle String
    # allocations and is recommended when reusing the same weights map.
    def self.compute_signature_slice_weighted_hashed(text : String, weights_hashed : Hash(UInt64, Float64)) : Slice(UInt32)
      num_hashes, _, _, shingle_size, min_words = config

      normalized = text.downcase.strip
      return Slice(UInt32).new(num_hashes, 0_u32) if normalized.empty?

      word_count = normalized.split(/\s+/).size
      return Slice(UInt32).new(num_hashes, 0_u32) if word_count < min_words

      return Slice(UInt32).new(num_hashes, 0_u32) if normalized.size < shingle_size

      signature = Slice(UInt32).new(num_hashes, UInt32::MAX)
      roller = ShingleRoller.new(shingle_size)
      def_weight = default_weight

      normalized.each_byte do |byte|
        if h64 = roller.roll(byte)
          weight = weights_hashed[h64]? || def_weight
          update_signature_weighted(signature, h64, weight)
        end
      end

      signature
    end

    # Helper to compute the rolling shingle hash for a given shingle string.
    # This is useful for converting a weights Hash(String, Float64) into
    # a Hash(UInt64, Float64) once, then using the hashed version for many
    # documents to avoid repeated string allocations.
    # Compute the rolling UInt64 hash for a given shingle String. Useful to
    # convert a String-keyed weights map into a hashed map with `prehash_weights`.
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

    # Convert a Hash(String, Float64) of shingle -> weight into a Hash(UInt64, Float64)
    # keyed by the shingle rolling hash. This should be called once for a weights map
    # that will be reused across many documents to avoid repeated shingle string
    # allocations during signature computation.
    # Convert a Hash(String, Float64) into a Hash(UInt64, Float64) where keys
    # are the rolling shingle hash. Call once for a weights map that will be
    # reused across many documents.
    def self.prehash_weights(weights : Hash(String, Float64)) : Hash(UInt64, Float64)
      hashed = Hash(UInt64, Float64).new
      weights.each do |shingle, weight|
        h = shingle_hash_for(shingle)
        hashed[h] = weight
      end
      hashed
    end

    # Convenience: take a Hash(String, Float64), prehash it once, and compute signature.
    # Useful when callers prefer the string-keyed API but still want the allocation
    # improvements of the hashed-weight path.
    # Convenience helper: prehash the supplied String-keyed weights and compute
    # the signature using the hashed-weighted path.
    def self.compute_signature_with_prehashed_weights(text : String, weights : Hash(String, Float64)) : Array(UInt32)
      hashed = prehash_weights(weights)
      compute_signature_slice_weighted_hashed(text, hashed).to_a
    end

    # Compute signature from pre-hashed UInt64 IDs
    #
    # This decouples hashing from the engine - the application handles
    # String -> UInt64 conversion (e.g., using xxHash, FNV, or custom hashing).
    # The engine operates purely on UInt64 hash values.
    #
    # ```
    # # App handles its own hashing
    # hashes = ["hello", "world", "test"].map { |s| my_hash_function(s) }
    # sig = LexisMinhash::Engine.compute_signature_from_hashes(hashes)
    # ```
    # Compute signature directly from an iterable of UInt64 hashes. This allows
    # callers to control the string-to-hash mapping (e.g., use xxHash or FNV)
    # and avoids duplicated hashing inside the engine.
    def self.compute_signature_from_hashes(hashes : Iterable(UInt64)) : Slice(UInt32)
      # Use default config coefficients to compute from pre-hashed values
      cfg = default_config
      num_hashes = cfg.signature_size
      a = cfg.a
      b = cfg.b

      signature = Slice(UInt32).new(num_hashes, UInt32::MAX)
      hashes.each do |h64|
        num_hashes.times do |i|
          combined_h = ((a[i] &* h64 &+ b[i]) >> 32).to_u32
          signature[i] = combined_h if combined_h < signature[i]
        end
      end

      signature
    end

    # Compute weighted signature from pre-hashed UInt64 IDs with weights
    #
    # Weights should be parallel to hashes or looked up by the caller.
    # Higher weights bias toward those hashes "winning" the min position.
    # Compute weighted signature from parallel iterables of hashes and weights.
    # The caller is responsible for aligning hashes and weights in the same
    # iteration order.
    def self.compute_signature_from_hashes(hashes : Iterable(UInt64), weights : Iterable(Float64)) : Slice(UInt32)
      cfg = default_config
      num_hashes = cfg.signature_size
      a = cfg.a
      b = cfg.b

      signature = Slice(UInt32).new(num_hashes, UInt32::MAX)
      hashes.zip(weights).each do |h64, weight|
        effective_weight = Math.max(weight, 0.0_f64)
        next if effective_weight <= 0.0_f64

        effective_value = effective_weight < 1.0_f64 ? Math.log(1.0_f64 + effective_weight) : effective_weight

        num_hashes.times do |i|
          combined_h = ((a[i] &* h64 &+ b[i]) >> 32).to_u32
          weighted_value = combined_h.to_f64 / effective_value
          weighted_h = (weighted_value % Float64.new(UInt32::MAX)).to_u32
          signature[i] = weighted_h if weighted_h < signature[i]
        end
      end

      signature
    end

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

    # Overlap coefficient for two sorted UInt64 slices
    def self.overlap_coefficient(a : Slice(UInt64), b : Slice(UInt64)) : Float64
      return 0.0 if a.empty? || b.empty?

      intersection = 0
      i = 0
      j = 0

      while i < a.size && j < b.size
        if a[i] == b[j]
          intersection += 1
          i += 1
          j += 1
        elsif a[i] < b[j]
          i += 1
        else
          j += 1
        end
      end

      intersection.to_f / {a.size, b.size}.min
    end

    # Overlap coefficient for two sorted UInt32 slices
    def self.overlap_coefficient(a : Slice(UInt32), b : Slice(UInt32)) : Float64
      return 0.0 if a.empty? || b.empty?

      intersection = 0
      i = 0
      j = 0

      while i < a.size && j < b.size
        if a[i] == b[j]
          intersection += 1
          i += 1
          j += 1
        elsif a[i] < b[j]
          i += 1
        else
          j += 1
        end
      end

      intersection.to_f / {a.size, b.size}.min
    end

    # Generate LSH bands from signature (Array or Slice)
    # Returns Array({Int32, UInt64}) with {band_index, band_hash} tuples
    # Optional `bands` parameter overrides Engine.config num_bands for custom LSH configurations
    def self.generate_bands(signature : Array(UInt32), bands : Int32? = nil) : Array({Int32, UInt64})
      _, config_bands, rows, _ = config
      num_bands = bands || config_bands
      band_hashes = [] of {Int32, UInt64}

      num_bands.times do |band_idx|
        band_slice = signature[band_idx * rows...(band_idx * rows + rows)]
        combined = 0_u64
        band_slice.each { |_hash| combined = (combined << 7) ^ _hash }
        band_hashes << {band_idx, combined}
      end

      band_hashes
    end

    # Generate band hashes from a signature slice (fast path)
    # Optional `bands` parameter overrides Engine.config num_bands for custom LSH configurations
    def self.generate_bands(signature : Slice(UInt32), bands : Int32? = nil) : Array({Int32, UInt64})
      _, config_bands, rows, _ = config
      num_bands = bands || config_bands
      band_hashes = [] of {Int32, UInt64}

      num_bands.times do |band_idx|
        band_slice = signature[band_idx * rows, rows]
        combined = 0_u64
        band_slice.each { |_hash| combined = (combined << 7) ^ _hash }
        band_hashes << {band_idx, combined}
      end

      band_hashes
    end

    # Estimate probability of detecting similar items
    # Based on s (similarity), b (bands), r (rows per band)
    def self.detection_probability(similarity : Float64) : Float64
      _, bands, rows, _ = config
      s_r = similarity ** rows
      1.0_f64 - (1.0_f64 - s_r) ** bands
    end

    # Convert Slice(UInt32) or Array(UInt32) to Bytes for storage
    def self.signature_to_bytes(signature : Array(UInt32) | Slice(UInt32)) : Bytes
      bytes = Bytes.new(signature.size * sizeof(UInt32))
      signature.each_with_index do |val, idx|
        bytes[idx * sizeof(UInt32) + 0] = (val & 0xFF).to_u8
        bytes[idx * sizeof(UInt32) + 1] = ((val >> 8) & 0xFF).to_u8
        bytes[idx * sizeof(UInt32) + 2] = ((val >> 16) & 0xFF).to_u8
        bytes[idx * sizeof(UInt32) + 3] = ((val >> 24) & 0xFF).to_u8
      end
      bytes
    end

    # Convert Bytes back to Array(UInt32) - default for backward compatibility
    def self.bytes_to_signature(bytes : Bytes) : Array(UInt32)
      return [] of UInt32 if bytes.empty?

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

    # Convert Bytes to Slice(UInt32) - for performance-critical code
    def self.bytes_to_signature_slice(bytes : Bytes) : Slice(UInt32)
      return Slice(UInt32).new(0) if bytes.empty?

      signature = Slice(UInt32).new(bytes.size // sizeof(UInt32))
      signature.size.times do |idx|
        signature[idx] = bytes[idx * sizeof(UInt32) + 0].to_u32 |
                         (bytes[idx * sizeof(UInt32) + 1].to_u32 << 8) |
                         (bytes[idx * sizeof(UInt32) + 2].to_u32 << 16) |
                         (bytes[idx * sizeof(UInt32) + 3].to_u32 << 24)
      end
      signature
    end
  end
end
