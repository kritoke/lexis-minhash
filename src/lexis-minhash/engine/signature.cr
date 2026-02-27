module LexisMinhash
  module Engine
    # Signature-related helpers split out of engine.cr

    # Pure signature computation using an explicit Config. Returns a Slice(UInt32).
    # This function is deterministic given the same config and text.
    def self.compute_signature_with_config(cfg : Config, text : String) : Slice(UInt32)
      num_hashes = cfg.signature_size
      shingle_size = cfg.shingle_size
      min_words = cfg.min_words

      normalized = text.downcase.strip
      return Slice(UInt32).new(num_hashes, 0_u32) if normalized.empty?
      word_count = normalized.split(/\s+/).size
      return Slice(UInt32).new(num_hashes, 0_u32) if word_count < min_words
      return Slice(UInt32).new(num_hashes, 0_u32) if normalized.size < shingle_size

      signature = Slice(UInt32).new(num_hashes, UInt32::MAX)
      a = cfg.a
      b = cfg.b

      shingles_hashes(normalized, shingle_size) do |h64|
        num_hashes.times do |i|
          combined_h = ((a[i] &* h64 &+ b[i]) >> 32).to_u32
          signature[i] = combined_h if combined_h < signature[i]
        end
      end

      signature
    end

    # Compute signature from pre-hashed UInt64 IDs
    def self.compute_signature_from_hashes(hashes : Iterable(UInt64)) : Slice(UInt32)
      num_hashes = default_config.signature_size
      a = default_config.a
      b = default_config.b

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
    def self.compute_signature_from_hashes(hashes : Iterable(UInt64), weights : Iterable(Float64)) : Slice(UInt32)
      num_hashes = default_config.signature_size
      a = default_config.a
      b = default_config.b

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
  end
end
