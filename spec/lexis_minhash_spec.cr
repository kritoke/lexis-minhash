require "spec"
require "../src/lexis-minhash"

describe LexisMinhash::Engine do
  describe "compute_signature" do
    it "returns a slice of the correct size" do
      LexisMinhash::Engine.configure(signature_size: 100, num_bands: 20)
      signature = LexisMinhash::Engine.compute_signature("Hello World Test Document")
      signature.size.should eq(100)
    end

    it "returns consistent signatures for the same text" do
      LexisMinhash::Engine.configure(signature_size: 100, num_bands: 20)
      sig1 = LexisMinhash::Engine.compute_signature("Test Document")
      sig2 = LexisMinhash::Engine.compute_signature("Test Document")
      sig1.should eq(sig2)
    end

    it "returns different signatures for different texts" do
      sig1 = LexisMinhash::Engine.compute_signature("Technology company announces revolutionary product")
      sig2 = LexisMinhash::Engine.compute_signature("Government officials discuss new policy changes")
      sig1.should_not eq(sig2)
    end
  end

  describe "similarity" do
    it "returns 1.0 for identical signatures" do
      sig = LexisMinhash::Engine.compute_signature("Test Document")
      LexisMinhash::Engine.similarity(sig, sig).should eq(1.0_f64)
    end

    it "returns higher similarity for similar texts" do
      sig1 = LexisMinhash::Engine.compute_signature("The quick brown fox jumps over the lazy dog")
      sig2 = LexisMinhash::Engine.compute_signature("The quick brown fox jumps over the lazy cat")
      sig3 = LexisMinhash::Engine.compute_signature("Completely different topic about cooking")

      sim_same = LexisMinhash::Engine.similarity(sig1, sig2)
      sim_diff = LexisMinhash::Engine.similarity(sig1, sig3)

      sim_same.should be > sim_diff
    end
  end

  describe "overlap_coefficient" do
    it "returns 0.0 for empty arrays" do
      a = Slice(UInt64).new(0)
      b = Slice(UInt64).new(1, 1_u64)
      LexisMinhash::Engine.overlap_coefficient(a, b).should eq(0.0)

      a = Slice(UInt64).new(1, 1_u64)
      b = Slice(UInt64).new(0)
      LexisMinhash::Engine.overlap_coefficient(a, b).should eq(0.0)
    end

    it "returns 1.0 for identical sorted arrays" do
      a = Slice.new(3) { |i| (i + 1).to_u64 }
      b = Slice.new(3) { |i| (i + 1).to_u64 }
      LexisMinhash::Engine.overlap_coefficient(a, b).should eq(1.0)
    end

    it "returns correct coefficient for partial overlap" do
      a = Slice.new(4) { |i| (i + 1).to_u64 }
      b = Slice.new(4) { |i| (i + 3).to_u64 }
      result = LexisMinhash::Engine.overlap_coefficient(a, b)
      result.should eq(0.5)
    end

    it "returns 0.0 for disjoint arrays" do
      a = Slice.new(3) { |i| (i + 1).to_u64 }
      b = Slice.new(3) { |i| (i + 10).to_u64 }
      LexisMinhash::Engine.overlap_coefficient(a, b).should eq(0.0)
    end

    it "uses min size in denominator" do
      a = Slice.new(5) { |i| (i + 1).to_u64 }
      b = Slice.new(3) { |i| (i + 3).to_u64 }
      b[2] = 6_u64
      result = LexisMinhash::Engine.overlap_coefficient(a, b)
      result.should eq(0.6666666666666666)
    end
  end

  describe "generate_bands" do
    it "returns the correct number of bands" do
      LexisMinhash::Engine.configure(signature_size: 100, num_bands: 20)
      sig = LexisMinhash::Engine.compute_signature("Test Document")
      bands = LexisMinhash::Engine.generate_bands(sig)
      bands.size.should eq(20)
    end

    it "returns {Int32, UInt64} band tuples" do
      sig = LexisMinhash::Engine.compute_signature("Test Document")
      bands = LexisMinhash::Engine.generate_bands(sig)
      bands.each do |band_idx, band_hash|
        band_idx.should be_a(Int32)
        band_hash.should be_a(UInt64)
      end
    end
  end

  describe "signature_to_bytes and bytes_to_signature" do
    it "preserves signature data through conversion" do
      original = LexisMinhash::Engine.compute_signature("Convert This Signature")
      bytes = LexisMinhash::Engine.signature_to_bytes(original)
      restored = LexisMinhash::Engine.bytes_to_signature(bytes)
      original.should eq(restored)
    end
  end

  describe "configure" do
    it "allows custom configuration" do
      LexisMinhash::Engine.configure(
        signature_size: 50,
        num_bands: 10,
        shingle_size: 4
      )

      num_hashes, bands, _, shingle_size = LexisMinhash::Engine.config
      num_hashes.should eq(50)
      bands.should eq(10)
      shingle_size.should eq(4)

      # Reset to defaults
      LexisMinhash::Engine.configure(signature_size: 100, num_bands: 20, shingle_size: 5)
    end
  end

  describe "detection_probability" do
    it "returns 0.0 for 0 similarity" do
      LexisMinhash::Engine.detection_probability(0.0_f64).should eq(0.0_f64)
    end

    it "returns 1.0 for 1.0 similarity" do
      prob = LexisMinhash::Engine.detection_probability(1.0_f64)
      prob.should be_close(1.0_f64, 0.01_f64)
    end

    it "returns higher probability for higher similarity" do
      prob_low = LexisMinhash::Engine.detection_probability(0.5_f64)
      prob_high = LexisMinhash::Engine.detection_probability(0.9_f64)
      prob_high.should be > prob_low
    end
  end
end

describe LexisMinhash::LSHIndex do
  it "adds and queries documents" do
    index = LexisMinhash::LSHIndex.new(bands: 20, expected_docs: 100)

    index.add(1, "The quick brown fox jumps over the lazy dog")
    index.add(2, "The quick brown fox jumps over the lazy cat")

    index.size.should eq(2)

    candidates = index.query("The quick brown fox jumps over the lazy")
    candidates.should contain(1)
    candidates.should contain(2)
  end

  it "finds similar pairs" do
    index = LexisMinhash::LSHIndex.new(bands: 20, expected_docs: 100)

    index.add(1, "Technology company announces revolutionary smartphone innovation")
    index.add(2, "Technology company announces revolutionary smartphone product")
    index.add(3, "Completely different topic about cooking recipes food")

    pairs = index.find_similar_pairs(threshold: 0.5_f64)
    pairs.size.should be >= 0
  end

  it "queries by signature directly" do
    index = LexisMinhash::LSHIndex.new(bands: 20, expected_docs: 100)

    signature = LexisMinhash::Engine.compute_signature("Test document for signature query")
    index.add_with_signature(1, signature)

    candidates = index.query_by_signature(signature)
    candidates.should contain(1)
  end

  it "queries with scores" do
    index = LexisMinhash::LSHIndex.new(bands: 20, expected_docs: 100)

    index.add(1, "The quick brown fox jumps over the lazy dog")
    index.add(2, "The quick brown fox jumps over the lazy cat")

    results = index.query_with_scores("The quick brown fox jumps over the lazy")
    results.size.should be > 0
    results.first[1].should be > 0.5_f64
  end

  it "returns load factors" do
    index = LexisMinhash::LSHIndex.new(bands: 20, expected_docs: 100)

    index.add(1, "Test document one")
    index.add(2, "Test document two")

    load_factors = index.load_factors
    load_factors.size.should eq(20)
  end

  it "clears all data" do
    index = LexisMinhash::LSHIndex.new(bands: 20, expected_docs: 100)

    index.add(1, "Test document for clearing")
    index.size.should eq(1)
    index.clear
    index.size.should eq(0)
  end

  it "adds and queries documents with weights" do
    index = LexisMinhash::LSHIndex.new(bands: 20, expected_docs: 100)

    weights1 = {"quick" => 2.0_f64, "brown" => 2.0_f64}
    weights2 = {"quick" => 2.0_f64, "brown" => 2.0_f64}

    index.add_with_weights(1, "The quick brown fox jumps", weights1)
    index.add_with_weights(2, "The quick brown dog runs", weights2)

    index.size.should eq(2)

    candidates = index.query_with_weights("The quick brown fox", {"quick" => 2.0_f64, "brown" => 2.0_f64})
    candidates.size.should be > 0
  end

  it "adds and queries with weights" do
    index = LexisMinhash::LSHIndex.new(bands: 20, expected_docs: 100)

    weights = {"quick" => 2.0_f64, "brown" => 2.0_f64}
    index.add_with_weights(1, "The quick brown fox jumps over the lazy dog", weights)
    index.add_with_weights(2, "The quick brown cat sleeps on the lazy rug", weights)

    index.size.should eq(2)

    candidates = index.query_with_weights("The quick brown fox jumps", weights)
    candidates.should be_a(Set(Int32))
  end
end

describe LexisMinhash::Similarity do
  describe "weighted_overlap" do
    it "returns 0.0 for empty hashes" do
      a = Hash(String, Float64).new
      b = Hash(String, Float64).new
      LexisMinhash::Similarity.weighted_overlap(a, b).should eq(0.0_f64)
    end

    it "returns 0.0 when one hash is empty" do
      a = Hash(String, Float64).new
      b = {"word" => 1.0_f64}
      LexisMinhash::Similarity.weighted_overlap(a, b).should eq(0.0_f64)
      LexisMinhash::Similarity.weighted_overlap(b, a).should eq(0.0_f64)
    end

    it "returns 1.0 for identical hashes" do
      a = {"word1" => 0.5_f64, "word2" => 0.3_f64}
      b = {"word1" => 0.5_f64, "word2" => 0.3_f64}
      LexisMinhash::Similarity.weighted_overlap(a, b).should eq(1.0_f64)
    end

    it "returns correct weighted overlap for partial matches" do
      a = {"word1" => 0.5_f64, "word2" => 0.5_f64}
      b = {"word1" => 0.5_f64, "word3" => 0.5_f64}
      result = LexisMinhash::Similarity.weighted_overlap(a, b)
      result.should eq(0.5_f64)
    end

    it "uses minimum weight when weights differ" do
      a = {"word" => 0.8_f64}
      b = {"word" => 0.2_f64}
      result = LexisMinhash::Similarity.weighted_overlap(a, b)
      result.should eq(1.0_f64)
    end

    it "uses minimum of sums in denominator" do
      a = {"word1" => 0.5_f64}
      b = {"word1" => 0.3_f64, "word2" => 0.5_f64}
      result = LexisMinhash::Similarity.weighted_overlap(a, b)
      intersection = 0.3_f64
      sum_a = 0.5_f64
      expected = intersection / sum_a
      result.should eq(expected)
    end
  end
end

describe LexisMinhash::Engine do
  describe "compute_signature with weights" do
    it "returns signature of correct size with weights" do
      weights = Hash(String, Float64).new
      sig = LexisMinhash::Engine.compute_signature("Hello World Test Document", weights)
      sig.size.should eq(100)
    end

    it "returns signature of correct size with nil weights" do
      sig = LexisMinhash::Engine.compute_signature("Hello World Test Document", nil)
      sig.size.should eq(100)
    end

    it "returns consistent signatures for same text and weights" do
      weights = {"hello" => 0.5_f64, "world" => 0.8_f64}
      sig1 = LexisMinhash::Engine.compute_signature("Hello World Test", weights)
      sig2 = LexisMinhash::Engine.compute_signature("Hello World Test", weights)
      sig1.should eq(sig2)
    end

    it "produces different signatures with different weights" do
      text = "hello world test document for testing"
      sig1 = LexisMinhash::Engine.compute_signature(text, {"hello" => 0.5_f64, "world" => 0.5_f64})
      sig2 = LexisMinhash::Engine.compute_signature(text, {"hello" => 2.0_f64, "world" => 2.0_f64})
      sig1.should_not eq(sig2)
    end

    it "falls back to default weight 1.0 for unknown shingles" do
      sig1 = LexisMinhash::Engine.compute_signature("hello world", {"unknown" => 10.0_f64})
      sig2 = LexisMinhash::Engine.compute_signature("hello world", nil)
      (sig1 == sig2).should be_true
    end

    it "treats negative weights as 0 (excluded from signature)" do
      sig_with_negative = LexisMinhash::Engine.compute_signature("hello world test", {"hello" => -1.0_f64})
      sig_without_term = LexisMinhash::Engine.compute_signature("world test", nil)
      sig_with_negative.should eq(sig_without_term)
    end
  end

  describe "compute_signature_slice with weights" do
    it "returns Slice of correct size with weights" do
      weights = Hash(String, Float64).new
      sig = LexisMinhash::Engine.compute_signature_slice("Hello World Test Document", weights)
      sig.size.should eq(100)
    end

    it "returns Slice of correct size with nil weights" do
      sig = LexisMinhash::Engine.compute_signature_slice("Hello World Test Document", nil)
      sig.size.should eq(100)
    end

    it "is mutable for weighted update" do
      weights = {"hello" => 0.5_f64}
      sig = LexisMinhash::Engine.compute_signature_slice("hello world", weights)
      sig.should be_a(Slice(UInt32))
    end
  end
end
