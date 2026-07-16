module LexisMinhash
  module Engine
    # Serialization helpers for converting signatures to/from byte representations.

    def self.signature_to_bytes(signature : Array(UInt32) | Slice(UInt32)) : Bytes
      bytes = Bytes.new(signature.size * sizeof(UInt32))
      signature.each_with_index do |val, idx|
        offset = idx * sizeof(UInt32)
        bytes[offset + 0] = (val & 0xFF).to_u8
        bytes[offset + 1] = ((val >> 8) & 0xFF).to_u8
        bytes[offset + 2] = ((val >> 16) & 0xFF).to_u8
        bytes[offset + 3] = ((val >> 24) & 0xFF).to_u8
      end
      bytes
    end

    def self.bytes_to_signature(bytes : Bytes) : Array(UInt32)
      return [] of UInt32 if bytes.empty?

      count = bytes.size // sizeof(UInt32)
      Array(UInt32).new(count) do |idx|
        read_uint32_le(bytes, idx * sizeof(UInt32))
      end
    end

    def self.bytes_to_signature_slice(bytes : Bytes) : Slice(UInt32)
      return Slice(UInt32).new(0) if bytes.empty?

      count = bytes.size // sizeof(UInt32)
      Slice(UInt32).new(count) do |idx|
        read_uint32_le(bytes, idx * sizeof(UInt32))
      end
    end

    # Read a little-endian UInt32 from a byte slice at the given offset
    private def self.read_uint32_le(bytes : Bytes, offset : Int32) : UInt32
      bytes[offset + 0].to_u32 |
        (bytes[offset + 1].to_u32 << 8) |
        (bytes[offset + 2].to_u32 << 16) |
        (bytes[offset + 3].to_u32 << 24)
    end
  end
end
