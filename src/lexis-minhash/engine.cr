# Engine implementation and core types for LexisMinhash
#
# This file contains the main engine implementation: rolling shingling,
# MinHash signature generation (weighted and unweighted), helpers for
# prehashing weights, and serialization helpers. The `Signature` struct is a
# convenient wrapper for signatures with to_blob/from_blob helpers.
module LexisMinhash
  # Rolling hash for O(n) shingling
  #
  # ShingleRoller computes a rolling polynomial hash over a sliding window of
  # bytes (characters). It yields a UInt64 hash value once the window is full
  # and also exposes the current shingle as a String. Used by the Engine to
  # produce k-shingles for MinHash computation.
  class ShingleRoller
    P = 31_u64
    getter window_size : Int32
    @power = 1_u64
    @current_hash = 0_u64
    @buffer = Deque(UInt8).new

    # Create a roller for a window of `window_size` bytes
    def initialize(@window_size : Int32)
      (@window_size - 1).times { @power = @power &* P }
    end

    # Add a byte to the rolling window and return the current shingle hash when
    # the window is full. Returns `nil` until enough bytes have been fed.
    def roll(byte : UInt8) : UInt64?
      if @buffer.size == @window_size
        out_byte = @buffer.shift
        @current_hash = @current_hash &- (out_byte.to_u64 &* @power)
      end

      @buffer << byte
      @current_hash = (@current_hash &* P) &+ byte.to_u64

      return nil if @buffer.size < @window_size
      @current_hash
    end

    # Reset the internal state and clear the buffer
    def reset : Nil
      @current_hash = 0_u64
      @buffer.clear
    end

    # Returns the current shingle as a String when the window is full, otherwise
    # returns `nil`.
    def current_shingle : String?
      return nil if @buffer.size < @window_size
      String.build do |io|
        @buffer.each { |byte| io.write_byte(byte) }
      end
    end
  end

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
    @@a : Slice(UInt64) = Slice(UInt64).new(0)
    @@b : Slice(UInt64) = Slice(UInt64).new(0)
    @@num_hashes : Int32 = 100
    @@bands : Int32 = 20
    @@rows : Int32 = 5
    @@shingle_size : Int32 = 5
    @@min_words : Int32 = 4
    @@default_weight : Float64 = 1.0_f64
    @@initialized = false
    @@mutex = Mutex.new

    # Default configuration constants
    SIGNATURE_SIZE =     100
    NUM_BANDS      =      20
    ROWS_PER_BAND  =       5
    SHINGLE_SIZE   =       5
    MIN_WORDS      =       4
    DEFAULT_WEIGHT = 1.0_f64

    private def self.ensure_initialized
      return if @@initialized
      @@mutex.synchronize do
        return if @@initialized
        @@a = Slice(UInt64).new(@@num_hashes) { Random::Secure.rand(UInt64) | 1 }
        @@b = Slice(UInt64).new(@@num_hashes) { Random::Secure.rand(UInt64) }
        @@initialized = true
      end
    end

    # Configures the MinHash engine parameters
    #
    # ```
    # LexisMinhash::Engine.configure(
    #   signature_size: 100, # Number of hash functions
    #   num_bands: 20,       # Number of LSH bands
    #   shingle_size: 5,     # Character n-gram size (k-shingles)
    #   min_words: 4,        # Minimum words for valid signature
    #   default_weight: 1.0, # Default weight for unknown shingles in weighted MinHash
    #   seed: 12345          # Optional seed for reproducible hashes
    # )
    # ```
    #
    # **Seed Parameter**: When provided, uses a deterministic PRNG (PCG) to generate
    # hash coefficients. This ensures signatures are consistent across application restarts.
    # Omit or set to `nil` for random (secure) coefficients on each run.
    def self.configure(
      signature_size : Int32 = 100,
      num_bands : Int32 = 20,
      shingle_size : Int32 = 5,
      min_words : Int32 = 4,
      default_weight : Float64 = 1.0_f64,
      seed : Int64? = nil,
    ) : Nil
      @@mutex.synchronize do
        @@num_hashes = signature_size
        @@bands = num_bands
        if signature_size % num_bands != 0
          raise ArgumentError.new("signature_size must be divisible by num_bands")
        end
        @@rows = signature_size // num_bands
        @@shingle_size = shingle_size
        @@min_words = min_words
        @@default_weight = default_weight

        if seed
          seed_u64 = seed.to_u64
          a_arr = [] of UInt64
          b_arr = [] of UInt64
          signature_size.times do |i|
            a_arr << (((seed_u64 &* 6364136223846793005 &+ 1442695040888963407) &+ i.to_u64) | 1)
            b_arr << ((seed_u64 &* 6364136223846793005 &+ 1442695040888963407) &+ i.to_u64)
          end
          @@a = Slice.new(a_arr.to_unsafe, signature_size)
          @@b = Slice.new(b_arr.to_unsafe, signature_size)
        else
          @@a = Slice(UInt64).new(signature_size) { Random::Secure.rand(UInt64) | 1 }
          @@b = Slice(UInt64).new(signature_size) { Random::Secure.rand(UInt64) }
        end
        @@initialized = true
      end
    end

    # Return current engine configuration as a tuple:
    # `{signature_size, num_bands, rows_per_band, shingle_size, min_words, default_weight}`
    def self.config : {Int32, Int32, Int32, Int32, Int32, Float64}
      ensure_initialized
      @@mutex.synchronize do
        {@@num_hashes, @@bands, @@rows, @@shingle_size, @@min_words, @@default_weight}
      end
    end

    # Default weight used for shingles not present in a provided weights map
    def self.default_weight : Float64
      ensure_initialized
      @@default_weight
    end

    # Compute signature using rolling hash + multiply-shift
    # Returns Array(UInt32) for backward compatibility
    # This API is convenient but slower than `compute_signature_slice` which
    # returns a `Slice(UInt32)` directly for performance-critical code.
    def self.compute_signature(text : String) : Array(UInt32)
      compute_signature_slice(text).to_a
    end

    # Compute signature as Slice(UInt32) for performance-critical code
    def self.compute_signature_slice(text : String) : Slice(UInt32)
      num_hashes, _, _, shingle_size, min_words = config

      # Normalize to lowercase for case-insensitive matching
      normalized = text.downcase.strip

      # Return zeros for empty or too-short strings (backward compatibility)
      return Slice(UInt32).new(num_hashes, 0_u32) if normalized.empty?

      # Return zeros if word count is below minimum
      word_count = normalized.split(/\s+/).size
      return Slice(UInt32).new(num_hashes, 0_u32) if word_count < min_words

      # Return zeros if text is shorter than shingle size
      return Slice(UInt32).new(num_hashes, 0_u32) if normalized.size < shingle_size

      signature = Slice(UInt32).new(num_hashes, UInt32::MAX)
      roller = ShingleRoller.new(shingle_size)

      normalized.each_byte do |byte|
        if h64 = roller.roll(byte)
          update_signature(signature, h64)
        end
      end

      signature
    end

    private def self.update_signature(signature : Slice(UInt32), h64 : UInt64) : Nil
      num_hashes, _, _, _ = config
      a = @@a
      b = @@b

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
      num_hashes, _, _, _ = config
      a = @@a
      b = @@b

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
      num_hashes, _, _, _, _ = config

      signature = Slice(UInt32).new(num_hashes, UInt32::MAX)
      a = @@a
      b = @@b

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
      num_hashes, _, _, _, _ = config

      signature = Slice(UInt32).new(num_hashes, UInt32::MAX)
      a = @@a
      b = @@b

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
