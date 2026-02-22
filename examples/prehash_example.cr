require "../src/lexis-minhash"

# Example: prehash weight map and compute signatures using the hashed-weighted path

base_weights = {
  "quick" => 2.0_f64,
  "brown" => 2.0_f64,
  "jumps" => 1.5_f64,
}

text = "The quick brown fox jumps over the lazy dog"

puts "Original text: #{text}"

# Prehash the weights once
hashed = LexisMinhash::Engine.prehash_weights(base_weights)
puts "Prehashed #{hashed.size} weights"

# Compute signature using prehashed weights
sig_hashed = LexisMinhash::Engine.compute_signature(text, hashed)
puts "Signature (hashed weights) size: #{sig_hashed.size}"

# Convenience: compute signature and prehash internally
sig_conv = LexisMinhash::Engine.compute_signature_with_prehashed_weights(text, base_weights)
puts "Signature (convenience) size: #{sig_conv.size}"

puts "Done"
