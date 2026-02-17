# Lexis MinHash - Locality-Sensitive Hashing for text similarity detection
# Used to group duplicate or similar documents from various sources
require "deque"
require "mutex"
require "random/secure"
require "set"

require "./lexis-minhash/engine"
require "./lexis-minhash/index"

module LexisMinhash
  # Document interface for custom document types
  module Document
    abstract def text : String
  end

  # Simple document wrapper for text strings
  struct SimpleDocument
    include Document

    getter text : String

    def initialize(@text : String)
    end
  end
end

# Backward compatibility: allow Engine to accept Document interface
# Extension for Engine module to support Document types and Array signatures
module LexisMinhash::Engine
  # Compute signature from a Document (backward compatibility)
  def self.compute_signature(document : LexisMinhash::Document) : Slice(UInt32)
    compute_signature(document.text)
  end

  # Overload for Array(UInt32) signatures (backward compatibility)
  def self.similarity(sig1 : Array(UInt32), sig2 : Array(UInt32)) : Float64
    return 0.0_f64 if sig1.empty? || sig2.empty?
    return 0.0_f64 if sig1.size != sig2.size

    matches = 0
    sig1.size.times do |i|
      matches += 1 if sig1[i] == sig2[i]
    end

    matches.to_f64 / sig1.size.to_f64
  end

  # Overload for Array(UInt32) (backward compatibility)
  def self.generate_bands(signature : Array(UInt32)) : Array({Int32, UInt64})
    band_hashes = [] of {Int32, UInt64}
    _, bands, rows, _ = config

    bands.times do |band_idx|
      band_slice = signature[band_idx * rows...(band_idx * rows + rows)]
      combined = 0_u64
      band_slice.each { |_hash| combined = (combined << 7) ^ _hash }
      band_hashes << {band_idx, combined}
    end

    band_hashes
  end

  # Overload for Array(UInt32) (backward compatibility)
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

  # Convert Bytes to Array(UInt32) (backward compatibility)
  def self.bytes_to_signature_array(bytes : Bytes) : Array(UInt32)
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
end
