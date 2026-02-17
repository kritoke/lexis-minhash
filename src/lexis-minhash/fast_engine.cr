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
  end

  # Fast MinHash engine using rolling hash + multiply-shift
  # Significantly faster than SHA256-based Engine
  module FastEngine
    @@a : Slice(UInt64) = Slice(UInt64).new(100)
    @@b : Slice(UInt64) = Slice(UInt64).new(100)
    @@num_hashes : Int32 = 100
    @@bands : Int32 = 20
    @@rows : Int32 = 5
    @@shingle_size : Int32 = 5
    @@mutex = Mutex.new

    def self.configure(
      signature_size : Int32 = 100,
      num_bands : Int32 = 20,
      shingle_size : Int32 = 5,
    ) : Nil
      @@mutex.synchronize do
        @@num_hashes = signature_size
        @@bands = num_bands
        @@rows = signature_size // num_bands
        @@shingle_size = shingle_size
        @@a = Slice(UInt64).new(signature_size) { Random::Secure.rand(UInt64) | 1 }
        @@b = Slice(UInt64).new(signature_size) { Random::Secure.rand(UInt64) }
      end
    end

    def self.config : {Int32, Int32, Int32, Int32}
      @@mutex.synchronize do
        {@@num_hashes, @@bands, @@rows, @@shingle_size}
      end
    end

    # Compute signature using rolling hash + multiply-shift
    def self.compute_signature(text : String) : Slice(UInt32)
      num_hashes, _, _, shingle_size = config
      signature = Slice(UInt32).new(num_hashes, UInt32::MAX)
      roller = ShingleRoller.new(shingle_size)

      text.each_byte do |byte|
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

    # Compute similarity between two signatures
    def self.similarity(sig1 : Slice(UInt32), sig2 : Slice(UInt32)) : Float64
      return 0.0_f64 if sig1.empty? || sig2.empty?
      return 0.0_f64 if sig1.size != sig2.size

      matches = 0
      sig1.size.times do |i|
        matches += 1 if sig1[i] == sig2[i]
      end

      matches.to_f64 / sig1.size.to_f64
    end

    # Generate LSH bands from signature
    def self.generate_bands(signature : Slice(UInt32)) : Array(UInt64)
      _, bands, rows, _ = config
      band_hashes = [] of UInt64

      bands.times do |band_idx|
        band_slice = signature[band_idx * rows, rows]
        band_hashes << band_slice.hash.to_u64
      end

      band_hashes
    end

    # Convert Slice(UInt32) to Bytes for storage
    def self.signature_to_bytes(signature : Slice(UInt32)) : Bytes
      bytes = Bytes.new(signature.size * sizeof(UInt32))
      signature.each_with_index do |val, idx|
        bytes[idx * sizeof(UInt32) + 0] = (val & 0xFF).to_u8
        bytes[idx * sizeof(UInt32) + 1] = ((val >> 8) & 0xFF).to_u8
        bytes[idx * sizeof(UInt32) + 2] = ((val >> 16) & 0xFF).to_u8
        bytes[idx * sizeof(UInt32) + 3] = ((val >> 24) & 0xFF).to_u8
      end
      bytes
    end

    # Convert Bytes back to Slice(UInt32)
    def self.bytes_to_signature(bytes : Bytes) : Slice(UInt32)
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
