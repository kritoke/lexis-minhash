module LexisMinhash
  module Engine
    # Rolling hash for O(n) shingling with circular buffer optimization
    class ShingleRoller
      P = 31_u64
      getter window_size : Int32
      @power = 1_u64
      @current_hash = 0_u64
      @buffer = StaticArray(UInt8, Engine::MAX_SHINGLE_SIZE).new(0_u8)
      @head = 0
      @size = 0

      def initialize(@window_size : Int32)
        if @window_size > Engine::MAX_SHINGLE_SIZE
          raise ArgumentError.new("Shingle size #{@window_size} exceeds maximum supported size #{Engine::MAX_SHINGLE_SIZE}")
        end

        (@window_size - 1).times { @power = @power &* P }
      end

      def roll(byte : UInt8) : UInt64?
        if @size == @window_size
          # Remove oldest byte from hash
          out_index = @head
          out_byte = @buffer[out_index]
          @current_hash = @current_hash &- (out_byte.to_u64 &* @power)

          # Move head forward (circular)
          @head = (@head + 1) % MAX_SHINGLE_SIZE
        else
          @size += 1
        end

        # Add new byte
        tail_index = (@head + @size - 1) % MAX_SHINGLE_SIZE
        @buffer[tail_index] = byte
        @current_hash = (@current_hash &* P) &+ byte.to_u64

        return nil if @size < @window_size
        @current_hash
      end

      def reset : Nil
        @current_hash = 0_u64
        @head = 0
        @size = 0
      end

      def current_shingle : String?
        return nil if @size < @window_size
        String.build do |io|
          @window_size.times do |i|
            index = (@head + i) % MAX_SHINGLE_SIZE
            io.write_byte(@buffer[index])
          end
        end
      end
    end

    # Generate rolling shingle hashes (UInt64) for a text and window size `k`.
    # Yields each rolling hash to the provided block without allocating shingle
    # strings. This is a pure helper (no module-level mutation).
    def self.shingles_hashes(text : String, k : Int32, &)
      if k > Engine::MAX_SHINGLE_SIZE
        raise ArgumentError.new("Shingle size #{k} exceeds maximum supported size #{Engine::MAX_SHINGLE_SIZE}")
      end

      p = 31_u64
      power = 1_u64
      (k - 1).times { power = power &* p }
      current_hash = 0_u64
      buffer = StaticArray(UInt8, Engine::MAX_SHINGLE_SIZE).new(0_u8)
      head = 0
      size = 0

      text.each_byte do |byte|
        if size == k
          # Remove oldest byte
          out_byte = buffer[head]
          current_hash = current_hash &- (out_byte.to_u64 &* power)
          head = (head + 1) % MAX_SHINGLE_SIZE
        else
          size += 1
        end

        # Add new byte
        tail_index = (head + size - 1) % MAX_SHINGLE_SIZE
        buffer[tail_index] = byte
        current_hash = (current_hash &* p) &+ byte.to_u64

        if size >= k
          yield current_hash
        end
      end
    end

    # Generate rolling shingles with both hash and string representation.
    # Yields (UInt64 hash, String shingle) for each shingle in the text.
    # The String is allocated per shingle, but this avoids the overhead of
    # creating a ShingleRoller instance and checking for completion separately.
    def self.shingles_with_strings(text : String, k : Int32, &)
      if k > Engine::MAX_SHINGLE_SIZE
        raise ArgumentError.new("Shingle size #{k} exceeds maximum supported size #{Engine::MAX_SHINGLE_SIZE}")
      end

      p = 31_u64
      power = 1_u64
      (k - 1).times { power = power &* p }
      current_hash = 0_u64
      buffer = Array(UInt8).new(k)

      text.each_byte do |byte|
        if buffer.size == k
          current_hash = current_hash &- (buffer[0].to_u64 &* power)
          buffer.shift
        end
        buffer << byte
        current_hash = (current_hash &* p) &+ byte.to_u64
        if buffer.size >= k
          shingle_str = String.build { |io| buffer.each { |byte_val| io.write_byte(byte_val) } }
          yield current_hash, shingle_str
        end
      end
    end
  end
end

module LexisMinhash
  ShingleRoller = Engine::ShingleRoller
end
