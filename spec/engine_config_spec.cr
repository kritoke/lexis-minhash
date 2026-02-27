require "spec"
require "../src/lexis-minhash"

describe LexisMinhash::Engine do
  describe "generate_config determinism" do
    it "produces identical coefficients for the same seed" do
      c1 = LexisMinhash::Engine.generate_config(signature_size: 32, num_bands: 8, seed: 12345_i64)
      c2 = LexisMinhash::Engine.generate_config(signature_size: 32, num_bands: 8, seed: 12345_i64)
      c1.a.size.should eq(c2.a.size)
      c1.b.size.should eq(c2.b.size)
      same = true
      32.times do |i|
        same = false unless c1.a[i] == c2.a[i]
        same = false unless c1.b[i] == c2.b[i]
      end
      same.should be_true
    end

    it "produces different coefficients for different seeds" do
      c1 = LexisMinhash::Engine.generate_config(signature_size: 32, num_bands: 8, seed: 1_i64)
      c2 = LexisMinhash::Engine.generate_config(signature_size: 32, num_bands: 8, seed: 2_i64)
      # It's possible by extreme coincidence they match; assert at least one differs
      different = false
      32.times do |i|
        different = true if c1.a[i] != c2.a[i] || c1.b[i] != c2.b[i]
      end
      different.should be_true
    end
  end

  describe "shingles_hashes parity" do
    it "matches ShingleRoller outputs" do
      text = "hello world"
      k = 5
      # collect from shingles_hashes
      hashes = [] of UInt64
      LexisMinhash::Engine.shingles_hashes(text, k) do |hash_val|
        hashes << hash_val
      end

      # collect from ShingleRoller
      roller_hashes = [] of UInt64
      roller = LexisMinhash::ShingleRoller.new(k)
      text.each_byte do |byte_val|
        if hh = roller.roll(byte_val)
          roller_hashes << hh
        end
      end

      hashes.should eq(roller_hashes)
    end
  end

  describe "shingles_with_strings" do
    it "yields hash and string for each shingle" do
      text = "hello world"
      k = 5
      results = [] of {UInt64, String}
      LexisMinhash::Engine.shingles_with_strings(text, k) do |hash_val, shingle_str|
        results << {hash_val, shingle_str}
      end

      results.size.should eq(text.size - k + 1)
      results.each do |hash_val, shingle_str|
        hash_val.should be_a(UInt64)
        shingle_str.size.should eq(k)
      end
    end

    it "produces same hashes as shingles_hashes" do
      text = "the quick brown fox"
      k = 5

      hashes_from_hashes = [] of UInt64
      LexisMinhash::Engine.shingles_hashes(text, k) do |hash_val|
        hashes_from_hashes << hash_val
      end

      hashes_from_with_strings = [] of UInt64
      LexisMinhash::Engine.shingles_with_strings(text, k) do |hash_val, _str|
        hashes_from_with_strings << hash_val
      end

      hashes_from_hashes.should eq(hashes_from_with_strings)
    end
  end
end
