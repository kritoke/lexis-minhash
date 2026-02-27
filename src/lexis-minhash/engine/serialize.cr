module LexisMinhash
  module Engine
    # Serialization helpers extracted from engine.cr

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
