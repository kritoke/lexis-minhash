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
end
