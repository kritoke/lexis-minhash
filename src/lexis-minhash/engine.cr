module LexisMinhash
  # Rolling hash for O(n) shingling
  class ShingleRoller
    P = 31_u64
    getter window_size : Int32
    @power = 1_u64
    @current_hash = 0_u64
    @buffer = Deque(UInt8).new

    def initialize(@window_size : Int32)
      (@window_size - 1).times { @power = @power &* P }
    end

    # Returns nil until window is full, then returns hash
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

    def reset : Nil
      @current_hash = 0_u64
      @buffer.clear
    end

    def current_shingle : String?
      return nil if @buffer.size < @window_size
      String.build do |io|
        @buffer.each { |byte| io.write_byte(byte) }
      end
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
    #   default_weight: 1.0  # Default weight for unknown shingles in weighted MinHash
    # )
    # ```
    def self.configure(
      signature_size : Int32 = 100,
      num_bands : Int32 = 20,
      shingle_size : Int32 = 5,
      min_words : Int32 = 4,
      default_weight : Float64 = 1.0_f64,
    ) : Nil
      @@mutex.synchronize do
        @@num_hashes = signature_size
        @@bands = num_bands
        @@rows = signature_size // num_bands
        @@shingle_size = shingle_size
        @@min_words = min_words
        @@default_weight = default_weight
        @@a = Slice(UInt64).new(signature_size) { Random::Secure.rand(UInt64) | 1 }
        @@b = Slice(UInt64).new(signature_size) { Random::Secure.rand(UInt64) }
        @@initialized = true
      end
    end

    def self.config : {Int32, Int32, Int32, Int32, Int32, Float64}
      ensure_initialized
      @@mutex.synchronize do
        {@@num_hashes, @@bands, @@rows, @@shingle_size, @@min_words, @@default_weight}
      end
    end

    def self.default_weight : Float64
      ensure_initialized
      @@default_weight
    end

    # Compute signature using rolling hash + multiply-shift
    # Returns Array(UInt32) for backward compatibility
    def self.compute_signature(text : String) : Array(UInt32)
      num_hashes, _, _, shingle_size, min_words = config

      # Normalize to lowercase for case-insensitive matching
      normalized = text.downcase.strip

      # Return zeros for empty or too-short strings (backward compatibility)
      return Array(UInt32).new(num_hashes, 0_u32) if normalized.empty?

      # Return zeros if word count is below minimum
      word_count = normalized.split(/\s+/).size
      return Array(UInt32).new(num_hashes, 0_u32) if word_count < min_words

      # Return zeros if text is shorter than shingle size
      return Array(UInt32).new(num_hashes, 0_u32) if normalized.size < shingle_size

      signature = Slice(UInt32).new(num_hashes, UInt32::MAX)
      roller = ShingleRoller.new(shingle_size)

      normalized.each_byte do |byte|
        if h64 = roller.roll(byte)
          update_signature(signature, h64)
        end
      end

      signature.to_a
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
        compute_signature_weighted(text, weights)
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
      num_hashes, _, _, shingle_size, min_words = config

      normalized = text.downcase.strip
      return Array(UInt32).new(num_hashes, 0_u32) if normalized.empty?

      word_count = normalized.split(/\s+/).size
      return Array(UInt32).new(num_hashes, 0_u32) if word_count < min_words

      return Array(UInt32).new(num_hashes, 0_u32) if normalized.size < shingle_size

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

      signature.to_a
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

    def self.compute_signature_slice(text : String, weights : Hash(String, Float64)?) : Slice(UInt32)
      if weights
        compute_signature_slice_weighted(text, weights)
      else
        compute_signature_slice(text)
      end
    end

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
    def self.generate_bands(signature : Array(UInt32)) : Array({Int32, UInt64})
      _, bands, rows, _ = config
      band_hashes = [] of {Int32, UInt64}

      bands.times do |band_idx|
        band_slice = signature[band_idx * rows...(band_idx * rows + rows)]
        combined = 0_u64
        band_slice.each { |_hash| combined = (combined << 7) ^ _hash }
        band_hashes << {band_idx, combined}
      end

      band_hashes
    end

    def self.generate_bands(signature : Slice(UInt32)) : Array({Int32, UInt64})
      _, bands, rows, _ = config
      band_hashes = [] of {Int32, UInt64}

      bands.times do |band_idx|
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
