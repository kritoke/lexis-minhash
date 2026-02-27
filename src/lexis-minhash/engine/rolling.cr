module LexisMinhash
  module Engine
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

    # Generate rolling shingle hashes (UInt64) for a text and window size `k`.
    # Yields each rolling hash to the provided block without allocating shingle
    # strings. This is a pure helper (no module-level mutation).
    def self.shingles_hashes(text : String, k : Int32)
      p = 31_u64
      power = 1_u64
      (k - 1).times { power = power &* p }
      current_hash = 0_u64
      buffer = Deque(UInt8).new

      text.each_byte do |byte|
        if buffer.size == k
          out_byte = buffer.shift
          current_hash = current_hash &- (out_byte.to_u64 &* power)
        end
        buffer << byte
        current_hash = (current_hash &* p) &+ byte.to_u64
        if buffer.size >= k
          yield current_hash
        end
      end
    end
  end
end

module LexisMinhash
  ShingleRoller = Engine::ShingleRoller
end
