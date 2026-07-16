module LexisMinhash
  module Engine
    # Pure signature computation using an explicit Config. Returns a Slice(UInt32).
    # Deterministic given the same config and text.
    def self.compute_signature_with_config(cfg : Config, text : String) : Slice(UInt32)
      num_hashes = cfg.signature_size

      normalized = prepare_text(text, cfg)
      return Slice(UInt32).new(num_hashes, 0_u32) if normalized.nil?

      signature = Slice(UInt32).new(num_hashes, UInt32::MAX)

      shingles_hashes(normalized, cfg.shingle_size) do |h64|
        apply_hash_min(signature, h64, cfg)
      end

      signature
    end
  end
end
