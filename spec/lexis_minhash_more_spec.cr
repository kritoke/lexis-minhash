require "spec"
require "../src/lexis-minhash"

describe "Engine seeded determinism" do
  it "produces identical signatures when configured with same seed" do
    LexisMinhash::Engine.configure(signature_size: 20, num_bands: 4, shingle_size: 3, min_words: 1, seed: 12345)
    sig1 = LexisMinhash::Engine.compute_signature("Deterministic seed test document")

    LexisMinhash::Engine.configure(signature_size: 20, num_bands: 4, shingle_size: 3, min_words: 1, seed: 12345)
    sig2 = LexisMinhash::Engine.compute_signature("Deterministic seed test document")

    sig1.should eq(sig2)

    # different seed should likely produce different signature
    LexisMinhash::Engine.configure(signature_size: 20, num_bands: 4, shingle_size: 3, min_words: 1, seed: 54321)
    sig3 = LexisMinhash::Engine.compute_signature("Deterministic seed test document")
    sig3.should_not eq(sig1)

    # restore defaults for other tests
    LexisMinhash::Engine.configure(signature_size: 100, num_bands: 20, shingle_size: 5, min_words: 4)
  end
end

describe "Negative and zero weights behavior" do
  it "treats negative weights as excluded (clamped to 0)" do
    LexisMinhash::Engine.configure(min_words: 1)
    text = "hello world test document"

    # With negative weight, "hello" is excluded from signature
    # This should produce different result than no weights (which uses default 1.0)
    sig_no = LexisMinhash::Engine.compute_signature(text, nil)
    sig_neg = LexisMinhash::Engine.compute_signature(text, {"hello" => -10.0_f64})

    # Negative weight excludes the term, producing different signature than default weight
    sig_neg.should_not eq(sig_no)

    # Zero weight should also exclude (same as negative)
    sig_zero = LexisMinhash::Engine.compute_signature(text, {"hello" => 0.0_f64})
    sig_zero.should eq(sig_neg)

    # Hashed path should behave the same way
    hashed = LexisMinhash::Engine.prehash_weights({"hello" => -10.0_f64})
    sig_hashed = LexisMinhash::Engine.compute_signature(text, hashed)
    sig_hashed.should eq(sig_neg)

    # restore defaults
    LexisMinhash::Engine.configure(signature_size: 100, num_bands: 20, shingle_size: 5, min_words: 4)
  end
end

describe "LSHIndex edge cases" do
  it "handles small capacity and collisions, exposes load factors and size" do
    # small expected_docs to force tight tables and potential collisions
    index = LexisMinhash::LSHIndex.new(bands: 10, expected_docs: 1)
    texts = (1..5).map { |i| "Document number #{i} with some shared terms" }
    texts.each_with_index do |text, idx|
      index.add(idx + 1, text)
    end

    index.size.should eq(5)
    lf = index.load_factors
    lf.size.should eq(10)
    lf.each do |value|
      value.should be >= 0.0
      value.should be <= 1.0
    end
  end

  it "query_with_scores_by_signature returns sorted scores and finds similar pairs" do
    # Use fewer bands (10) for lower detection threshold to ensure candidates are found
    # Make docs 1 and 2 nearly identical for reliable LSH detection
    index = LexisMinhash::LSHIndex.new(bands: 10, expected_docs: 100)
    index.add(1, "apple banana orange fruit salad recipe with apple and banana")
    index.add(2, "apple banana orange fruit salad recipe with apple and banana")
    index.add(3, "completely unrelated cooking about pasta and sauce")

    # Query with exact match to ensure candidates are found
    results = index.query_with_scores("apple banana orange fruit salad recipe with apple and banana")
    results.should be_a(Array({Int32, Float64}))
    results.size.should be > 0
    # ensure sorted descending by score
    scores = results.map(&.at(1))
    scores.should eq(scores.sort!.reverse)

    # Nearly identical documents should be detected as similar pairs
    pairs = index.find_similar_pairs(threshold: 0.4_f64)
    found = pairs.any? { |pair| (pair[0] == 1 && pair[1] == 2) || (pair[0] == 2 && pair[1] == 1) }
    found.should be_true
  end
end
